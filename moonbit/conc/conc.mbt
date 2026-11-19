///|
/// One task behind the semaphore.  A separate function (rather than an
/// inline async closure) because the closure form is what the two toolchain
/// versions disagree about.
async fn[T] guarded(sem : @async.Semaphore, t : async () -> T) -> T {
  sem.acquire()
  let v = t()
  sem.release()
  v
}

///|
/// Run every task, at most `limit` at a time, preserving input order.
///
/// All tasks are spawned; the semaphore is what bounds concurrency, so this is
/// not a worker pool.  That is fine for the call sites here: the number of
/// tasks is bounded by the number of workers or cases, and coroutines are
/// cheap.
///
/// The parameter is `Int32` because the callers already hold an `Int32`
/// worker count, and `Int`/`Int32` do not implicitly convert.
pub async fn[T] all_limited(
  tasks : Array[async () -> T],
  limit : Int32,
) -> Array[T] {
  let n = if limit < 1 { 1 } else { limit }
  if tasks.length() <= n {
    return @async.all(tasks)
  }
  let sem = @async.Semaphore(n)
  let wrapped : Array[async () -> T] = []
  let mut i = 0
  while i < tasks.length() {
    let t = tasks[i]
    wrapped.push(() => guarded(sem, t))
    i += 1
  }
  @async.all(wrapped)
}
