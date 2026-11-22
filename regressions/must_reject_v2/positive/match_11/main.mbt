enum E11 { A; B }
fn f(e : E11) -> Int { match e { A => 11 } }
fn main { println(f(A)) }
