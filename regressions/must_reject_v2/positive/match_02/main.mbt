enum E2 { A; B }
fn f(e : E2) -> Int { match e { A => 2 } }
fn main { println(f(A)) }
