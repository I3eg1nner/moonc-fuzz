pub async fn[T] pick(select : (Int) -> T?) -> T? {
  @aio.pause()
  let x : Int = 0
  select('a')
}
