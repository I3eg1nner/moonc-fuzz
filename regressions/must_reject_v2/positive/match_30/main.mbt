enum E30 { A; B }
fn f(e : E30) -> Int { match e { A => 30 } }
fn main { println(f(A)) }
