type ExternRef

pub extern "C" fn get_ext_ref() -> ExternRef = "get_ext_ref"

fn main {
  let ext_ref = get_ext_ref()
  let arr : Array[ExternRef] = [ext_ref, ext_ref, ext_ref]
  println(arr.length())
  let arr2 : Array[ExternRef] = Array::make(3, ext_ref)
  println(arr2.length())
}
