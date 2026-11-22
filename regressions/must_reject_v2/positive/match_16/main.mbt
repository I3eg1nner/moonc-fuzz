enum E16 { A; B }
fn f(e : E16) -> Int { match e { A => 16 } }
fn main { println(f(A)) }
