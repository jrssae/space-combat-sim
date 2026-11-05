// Worker threads for the native core's per-ship passes (M4-T18, docs/architecture.md 17.13). A pass hands every item
// (a thinking ship, a flying ship) to one call that reads only frozen, shared data and writes only that item, with a
// scratch of its own per worker thread, so one thread and six give the same bits. Engine-free: no Godot type here.
use std::sync::Mutex;
use std::sync::atomic::{AtomicI64, Ordering};

use rayon::prelude::*;

/// The most threads a pass may use.
pub const MAX_THREADS: usize = 64;
/// Below this many items a pass stays on the calling thread: waking the workers costs more than they save (the
/// numbers that chose it are in the milestone's Cycle log, M4-T18).
pub const DEFAULT_MIN_ITEMS: usize = 16;
// Chunks per thread in a parallel pass: enough for the idle workers to steal from the busy ones.
const CHUNKS_PER_THREAD: usize = 4;

/// The core's worker threads: none for one thread, else a pool of that many.
pub struct Threads {
    count: usize,
    pool: Option<rayon::ThreadPool>,
    min_items: usize,
    parallel_passes: AtomicI64,
}

impl Default for Threads {
    fn default() -> Self {
        Self {
            count: 1,
            pool: None,
            min_items: DEFAULT_MIN_ITEMS,
            parallel_passes: AtomicI64::new(0),
        }
    }
}

impl Threads {
    /// Uses `count` threads from the next pass on (1 or less: the calling thread alone). Returns the count in use.
    pub fn set_count(&mut self, count: usize) -> usize {
        let count = count.clamp(1, MAX_THREADS);
        if count == self.count && (count == 1 || self.pool.is_some()) {
            return self.count;
        }
        self.pool = if count > 1 {
            rayon::ThreadPoolBuilder::new()
                .num_threads(count)
                .thread_name(|i| format!("scs-core-{i}"))
                .build()
                .ok()
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

    /// The fewest items a pass runs in parallel with.
    pub fn min_items(&self) -> usize {
        self.min_items
    }

    /// Sets the fewest items a pass runs in parallel with (the benches choose it; at least 2).
    pub fn set_min_items(&mut self, min_items: usize) {
        self.min_items = min_items.max(2);
    }

    /// Passes that ran in parallel since the core was made.
    pub fn parallel_passes(&self) -> i64 {
        self.parallel_passes.load(Ordering::Relaxed)
    }

    /// Calls `each` on every item, with the scratch of the worker thread that runs it. With one thread, or fewer items
    /// than the threshold, every item runs on the calling thread with the first scratch. `each` must read only shared,
    /// frozen data and write only its item and the scratch, clearing what it reads of the scratch first.
    pub fn run<T, W, F>(&self, items: &mut [T], workers: &[Mutex<W>], each: F)
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
            .filter(|_| items.len() >= self.min_items && workers.len() >= self.count);
        let Some(pool) = pool else {
            let mut worker = lock(&workers[0]);
            for item in items.iter_mut() {
                each(item, &mut worker);
            }
            return;
        };
        self.parallel_passes.fetch_add(1, Ordering::Relaxed);
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
