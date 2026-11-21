pub async fn[T] pick(select : (Int) -> T?) -> T? {

raise Failure("x")
  @aio.pause()
  select(1)
}
