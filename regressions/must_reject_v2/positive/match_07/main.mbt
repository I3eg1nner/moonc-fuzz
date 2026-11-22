enum E7 { A; B }
fn f(e : E7) -> Int { match e { A => 7 } }
fn main { println(f(A)) }
