// Worker threads for the native core's per-ship passes (M4-T18, docs/architecture.md 17.13). A pass hands every item
// (a thinking ship, a flying ship) to one call that reads only frozen, shared data and writes only that item, with a
// scratch of its own per worker thread, so one thread and six give the same bits. Engine-free: no Godot type here.
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rayon::prelude::*;

/// The most threads a pass may use.
pub const MAX_THREADS: usize = 64;
/// The passes, each with its own threshold below which it stays on the calling thread.
#[derive(Clone, Copy)]
pub enum Pass {
    Brains = 0,
    Flight = 1,
}
/// The thresholds by pass: below them waking the workers costs more than they save, in the mean or in the slow ticks
/// (the numbers that chose them are in the milestone's Cycle log, M4-T18). The brains cost the 1 % slowest ticks at 19 to
/// 36 thinks and gain at 89 to 146; 48 sits above the measured losses with a margin, the gap between is not measured. The
/// flight kernel is too short to gain at any measured count.
pub const DEFAULT_MIN_ITEMS: [usize; 2] = [48, 1024];
// Chunks per thread in a parallel pass: enough for the idle workers to steal from the busy ones.
const CHUNKS_PER_THREAD: usize = 4;
// How long a shut-down pool's workers get to exit before the core stops waiting for them.
const JOIN_TIMEOUT: Duration = Duration::from_secs(5);

/// The core's worker threads: none for one thread, else a pool of that many.
pub struct Threads {
    count: usize,
    pool: Option<rayon::ThreadPool>,
    min_items: [usize; 2],
    parallel_passes: [AtomicI64; 2],
    // Workers spawned and not yet exited, across every pool this core made (a pool's workers are joined before the next).
    live: Arc<AtomicI64>,
}

impl Default for Threads {
    fn default() -> Self {
        Self {
            count: 1,
            pool: None,
            min_items: DEFAULT_MIN_ITEMS,
            parallel_passes: [AtomicI64::new(0), AtomicI64::new(0)],
            live: Arc::new(AtomicI64::new(0)),
        }
    }
}

// The workers are joined before the library can unload under them.
impl Drop for Threads {
    fn drop(&mut self) {
        self.shut_down();
    }
}

impl Threads {
    /// Uses `count` threads from the next pass on (1 or less: the calling thread alone). Returns the count in use.
    pub fn set_count(&mut self, count: usize) -> usize {
        let count = count.clamp(1, MAX_THREADS);
        if count == self.count && (count == 1 || self.pool.is_some()) {
            return self.count;
        }
        self.shut_down();
        self.pool = if count > 1 {
            let exited = Arc::clone(&self.live);
            let built = rayon::ThreadPoolBuilder::new()
                .num_threads(count)
                .thread_name(|i| format!("scs-core-{i}"))
                .exit_handler(move |_| {
                    exited.fetch_sub(1, Ordering::SeqCst);
                })
                .build()
                .ok();
            // Counted when spawned, so a worker still starting is waited for too.
            if built.is_some() {
                self.live.fetch_add(count as i64, Ordering::SeqCst);
            }
            built
        } else {
            None
        };
        self.count = if self.pool.is_some() { count } else { 1 };
        self.count
    }

    /// The threads a pass uses.
    pub fn count(&self) -> usize {
        self.count
    }

    /// The fewest items `pass` runs in parallel with.
    pub fn min_items(&self, pass: Pass) -> usize {
        self.min_items[pass as usize]
    }

    /// Sets the fewest items `pass` runs in parallel with (the benches and the tests choose it; at least 2).
    pub fn set_min_items(&mut self, pass: Pass, min_items: usize) {
        self.min_items[pass as usize] = min_items.max(2);
    }

    /// Passes that ran in parallel since the core was made, every pass together.
    pub fn parallel_passes(&self) -> i64 {
        self.parallel_passes
            .iter()
            .map(|p| p.load(Ordering::Relaxed))
            .sum()
    }

    /// Passes of one kind that ran in parallel since the core was made.
    pub fn parallel_passes_of(&self, pass: Pass) -> i64 {
        self.parallel_passes[pass as usize].load(Ordering::Relaxed)
    }

    /// Worker threads running now (0 with one thread, once the last pool's workers have exited).
    pub fn live_workers(&self) -> i64 {
        self.live.load(Ordering::SeqCst)
    }

    // Drops the pool and waits for its workers to exit (rayon signals them on drop but does not join them), so no worker
    // outlives the pool's owner. A worker that does not exit in time is left, and said so.
    fn shut_down(&mut self) {
        if self.pool.take().is_none() {
            return;
        }
        let deadline = Instant::now() + JOIN_TIMEOUT;
        while self.live.load(Ordering::SeqCst) > 0 {
            if Instant::now() > deadline {
                eprintln!(
                    "scs threads: {} worker(s) still running after the pool shut down",
                    self.live.load(Ordering::SeqCst)
                );
                return;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    /// Calls `each` on every item, with the scratch of the worker thread that runs it. With one thread, or fewer items
    /// than the threshold, every item runs on the calling thread with the first scratch. `each` must read only shared,
    /// frozen data and write only its item and the scratch, clearing what it reads of the scratch first.
    pub fn run<T, W, F>(&self, pass: Pass, items: &mut [T], workers: &[Mutex<W>], each: F)
    where
        T: Send,
        W: Send,
        F: Fn(&mut T, &mut W) + Sync,
    {
        if workers.is_empty() {
            return;
        }
        let pool = self
            .pool
            .as_ref()
            .filter(|_| items.len() >= self.min_items(pass) && workers.len() >= self.count);
        let Some(pool) = pool else {
            let mut worker = lock(&workers[0]);
            for item in items.iter_mut() {
                each(item, &mut worker);
            }
            return;
        };
        self.parallel_passes[pass as usize].fetch_add(1, Ordering::Relaxed);
        let chunk = items.len().div_ceil(self.count * CHUNKS_PER_THREAD).max(1);
        pool.install(|| {
            items.par_chunks_mut(chunk).for_each(|part| {
                let index = rayon::current_thread_index().unwrap_or(0) % workers.len();
                let mut worker = lock(&workers[index]);
                for item in part.iter_mut() {
                    each(item, &mut worker);
                }
            });
        });
    }
}

/// Grows `workers` to one scratch per thread of `threads` (scratches are kept between passes, so nothing is allocated
/// once they have grown).
pub fn ensure_workers<W: Default>(workers: &mut Vec<Mutex<W>>, threads: &Threads) {
    while workers.len() < threads.count().max(1) {
        workers.push(Mutex::new(W::default()));
    }
}

/// The machine's performance cores: the physical cores of the hybrid CPU's performance type (`/sys/devices/cpu_core`),
/// else of every online CPU, at most the CPUs this process may run on; 1 when nothing can be read.
pub fn performance_cores() -> usize {
    let allowed = std::thread::available_parallelism().map_or(1, |n| n.get());
    let list = std::fs::read_to_string("/sys/devices/cpu_core/cpus")
        .or_else(|_| std::fs::read_to_string("/sys/devices/system/cpu/online"))
        .unwrap_or_default();
    let mut cores: Vec<(String, String)> = Vec::new();
    for cpu in cpu_list(&list) {
        let topology = format!("/sys/devices/system/cpu/cpu{cpu}/topology");
        let core = std::fs::read_to_string(format!("{topology}/core_id")).unwrap_or_default();
        let package =
            std::fs::read_to_string(format!("{topology}/physical_package_id")).unwrap_or_default();
        let key = (package.trim().to_string(), core.trim().to_string());
        if !key.1.is_empty() && !cores.contains(&key) {
            cores.push(key);
        }
    }
    if cores.is_empty() {
        return allowed.max(1);
    }
    cores.len().min(allowed).max(1)
}

// The CPUs a sysfs list names ("0-11,16").
fn cpu_list(list: &str) -> Vec<usize> {
    let mut out = Vec::new();
    for part in list.trim().split(',').filter(|p| !p.is_empty()) {
        let mut ends = part.splitn(2, '-').map(|v| v.trim().parse::<usize>());
        match (ends.next(), ends.next()) {
            (Some(Ok(a)), Some(Ok(b))) if a <= b => out.extend(a..=b),
            (Some(Ok(a)), None) => out.push(a),
            _ => {}
        }
    }
    out
}

// A worker's scratch, even after a panic in another pass (the scratch is cleared before every use).
fn lock<W>(worker: &Mutex<W>) -> std::sync::MutexGuard<'_, W> {
    worker
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}
