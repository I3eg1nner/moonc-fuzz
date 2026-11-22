enum E14 { A; B }
fn f(e : E14) -> Int { match e { A => 14 } }
fn main { println(f(A)) }
