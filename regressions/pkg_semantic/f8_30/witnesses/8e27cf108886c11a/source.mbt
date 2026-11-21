pub async fn[T] pick(select : (Int) -> T?) -> T? {
  @aio.pause()
  raise Failure("x")
()
  select(1)
}
