fn compute() -> String {
  let z = 0.0
  let nz = -0.0
  let inf = 1.0 / z
  let nan = z / z
  "\{z.to_string()}|\{nz.to_string()}|\{inf.to_string()}|\{nan.to_string()}|\{(0.1 + 0.2).to_string()}|\{(1.0 / 3.0).to_string()}"
}
fn main { println(compute()) }
