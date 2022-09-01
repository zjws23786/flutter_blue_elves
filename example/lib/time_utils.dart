

class TimeUtils{

  static int dateToLong(String time){
    DateTime  dateTime = DateTime.parse(time);
    return dateTime.millisecondsSinceEpoch;
  }


}