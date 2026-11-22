enum E13 { A; B }
fn f(e : E13) -> Int { match e { A => 13 } }
fn main { println(f(A)) }
