enum E12 { A; B }
fn f(e : E12) -> Int { match e { A => 12 } }
fn main { println(f(A)) }
