fn compute() -> String {
  let a = 2.0
  let b = 0.5
  "\{(a.sqrt()).to_string()}|\{(b.floor()).to_string()}|\{(1.5).ceil().to_string()}|\{(-1.5).floor().to_string()}"
}
fn main { println(compute()) }
