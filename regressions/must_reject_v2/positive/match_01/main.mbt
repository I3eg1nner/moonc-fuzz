enum E1 { A; B }
fn f(e : E1) -> Int { match e { A => 1 } }
fn main { println(f(A)) }
