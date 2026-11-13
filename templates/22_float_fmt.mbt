fn compute() -> String {
  let x = 0.1
  let y = 1.0e21
  let z = 1.0e-7
  let w = -0.0
  "\{x.to_string()}|\{y.to_string()}|\{z.to_string()}|\{w.to_string()}|\{(0.0 / 0.0).to_string()}|\{(1.0 / 0.0).to_string()}"
}
fn main { println(compute()) }
