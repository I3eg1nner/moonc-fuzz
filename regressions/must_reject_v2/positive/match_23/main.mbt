enum E23 { A; B }
fn f(e : E23) -> Int { match e { A => 23 } }
fn main { println(f(A)) }
