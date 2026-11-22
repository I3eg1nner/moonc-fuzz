enum E6 { A; B }
fn f(e : E6) -> Int { match e { A => 6 } }
fn main { println(f(A)) }
