enum E15 { A; B }
fn f(e : E15) -> Int { match e { A => 15 } }
fn main { println(f(A)) }
