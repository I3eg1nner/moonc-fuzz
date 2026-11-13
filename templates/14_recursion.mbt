fn fib(n : Int) -> Int {
  if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}
fn compute() -> String {
  "\{fib(10)}|\{fib(20)}"
}
fn main { println(compute()) }
