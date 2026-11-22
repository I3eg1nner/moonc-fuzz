type ExternRef

extern "C" fn get_ext_ref() -> ExternRef = "get_ext_ref"
extern "C" fn handle_arr_ext_ref(arr: Array[ExternRef]) = "handle_arr_ext_ref"

fn main {
  let ext_ref = get_ext_ref()
  let arr = [ext_ref, ext_ref, ext_ref]
  handle_arr_ext_ref(arr)
}
