class StringUtils{

  static bool isEmpty(String? str){
    if(str == null || str.trim().length == 0){
      return true;
    }
    return false;
  }
}