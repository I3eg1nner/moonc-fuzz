fn compute() -> String {
  let x = 255
  let y = x.to_int64()
  let z = y * 1000000000L
  let u = 4294967295U
  let w = u + 1U
  "\{x}|\{y}|\{z}|\{u}|\{w}|\{x.to_byte()}"
}
fn main { println(compute()) }
