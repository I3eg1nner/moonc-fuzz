fn compute() -> String {
  let add = fn(x : Int) { fn(y : Int) { x + y } }
  let inc = add(1)
  let double = fn(x : Int) { x * 2 }
  let mut acc = 0
  for x in [1, 2, 3] {
    acc = acc + double(x)
  }
  "\{inc(41)}|\{acc}"
}
fn main { println(compute()) }
