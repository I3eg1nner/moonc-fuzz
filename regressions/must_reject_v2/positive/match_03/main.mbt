enum E3 { A; B }
fn f(e : E3) -> Int { match e { A => 3 } }
fn main { println(f(A)) }
