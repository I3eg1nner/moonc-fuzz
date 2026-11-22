struct P { x : Int; y : Int } derive(Show, Eq)
fn compute() -> String {
  let p = { x: 1, y: -2 }
  let q = { x: 3, y: 4 }
  "\{p.to_string()}|\{p == q}|\{p.x + q.y}"
}
fn main { println(compute()) }
