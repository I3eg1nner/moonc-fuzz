pub async fn[T] pick(select : (Int) -> T?) -> T? {
  @aio.pause()
  select(0)
}
