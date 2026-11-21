pub async fn[T] pick(select : (Int) -> T?) -> T? {

raise Failure("x")

let a : Array[Int] = []
  @aio.pause()
  select(1)
}
