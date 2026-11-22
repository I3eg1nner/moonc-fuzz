fn compute() -> String {
  let s = "abcdef"
  let i = 2
  let j = 5
  let t = if i >= 0 && j <= s.length() && i <= j { s[i:j] } else { "?" }
  let u = if s.length() > 0 { s[0:1] } else { "?" }
  "\{t}|\{u}|\{s.length()}"
}
fn main { println(compute()) }
