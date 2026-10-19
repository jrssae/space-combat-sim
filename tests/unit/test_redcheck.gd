extends GutTest
## Scratch branch only (M1-T03 red check): this test must fail so CI goes red. Never merge.


func test_deliberate_failure() -> void:
	assert_eq(1, 2, "deliberate failure to prove CI goes red")
