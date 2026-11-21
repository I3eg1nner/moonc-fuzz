pub async fn[T] pick(select : (Int) -> T?) -> T? {
  @aio.pause()
  let f = fn() { () }
  select('\u{10FFFF}')
}
