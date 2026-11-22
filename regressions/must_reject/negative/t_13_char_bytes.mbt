fn compute() -> String {
  let c = '中'
  let bytes = b"abc"
  "\{c.to_int()}|\{c}|\{bytes.length()}|\{bytes[0].to_int()}"
}
fn main { println(compute()) }
