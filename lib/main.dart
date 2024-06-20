import 'package:flutter/material.dart';  // 導入Flutter核心庫
import 'package:table_calendar/table_calendar.dart';  // 導入表格日曆庫
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:langchain/langchain.dart';
import 'package:langchain_google/langchain_google.dart';

void main() async{
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,  // 不顯示debug標誌
    home: MyApp(),  // 指定應用程序的首頁為MyApp小部件
  ));
}

class MyApp extends StatefulWidget {  // 定義MyApp小部件作為有狀態的小部件
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();  // 創建MyApp的狀態管理類
}
class Event {  // 定義事件類別
  int id; // 每個事件的唯一標識符
  String name; // 事件名稱
  DateTime timeFrom; // 開始時間
  DateTime timeTo; // 結束時間

  Event(this.id, this.name, this.timeFrom, this.timeTo);  // 事件類別的構造函數

  @override
  String toString() {  // 重寫toString方法，以便在列表中顯示事件的描述
    return '活動: $name \n時間: ${_formatTime(timeFrom)} ~~ ${_formatTime(timeTo)}';
  }

  String _formatTime(DateTime time) {  // 格式化時間，將時間轉換為特定格式
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;  // 取得小時，處理12小時制
    final minute = time.minute.toString().padLeft(2, '0');  // 取得分鐘，並補零到兩位數
    final period = time.hour >= 12 ? 'PM' : 'AM';  // 判斷上午或下午
    return '$hour:$minute $period';  // 返回格式化後的時間字符串
  }

  String _formatTimeforLine(DateTime time) {
    final formatter = DateFormat('hh:mm a');  // 使用 DateFormat 指定格式
    return formatter.format(time);  // 返回格式化後的時間字符串
  }

}
class _MyAppState extends State<MyApp> {  // MyApp的狀態類
  CalendarFormat _calendarFormat = CalendarFormat.month;  // 日曆格式，默認為月份格式
  DateTime _focusedDay = DateTime.now();  // 當前聚焦的日期，默認為當前日期
  DateTime? _selectedDay;  // 選中的日期
  Map<DateTime, List<Event>> events = {};  // 日期和對應事件的映射
  final TextEditingController _eventController = TextEditingController();  // 文本編輯器控制器，用於事件名稱輸入
  late final ValueNotifier<List<Event>> _selectedEvents;  // 存儲當前選中日期的事件列表的ValueNotifier
  TimeOfDay _from = TimeOfDay.now();  // 開始時間，默認為當前時間
  TimeOfDay _to = TimeOfDay.now();  // 結束時間，默認為當前時間
  String _nlpString = "";

  //提示變數
  final Map <int, String> eState ={
    -22: "活動名稱未填寫",
    -21: "輸入時間錯誤",
    -4: "編輯錯誤",
    -3: "刪除失敗",
    -2: "新增失敗",
    -1: "輸入格式錯誤",
    0: "新增成功",
    1: "刪除成功",
    2: "編輯成功"
  };

  // @錯誤及正確提示
  void _showErrorDialog(BuildContext errorContext, String text, String message) {
    showDialog(
      context: errorContext,
      builder: (BuildContext alertDialogContext) {
        return AlertDialog(
          title: Text(text),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(alertDialogContext).pop();
              },
              child: const Text("返回"),
            ),
          ],
        );
      },
    );
  }

  // @NlpTest
  Future<String> _nlpAnalyze(String sentence) async {
    print("開始NLP分析");
    try {
      final now = DateTime.now();
      final inputString = '''
              你是一個行事曆文本分析機器人，請幫我解析分析句子。
              須了解的概念如下，日期資訊皆須檢視這些概念：
              1.現在日期及時間為${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute}
              2.今天為星期 ${now.weekday}，星期的計算時間皆為今天或今天以後
              3.了解今天、明天、後天、昨天的概念，識別「今天」、「明天」、「後天」、「昨天」並根據第1點計算出相應的日期
              4.了解「星期」及「週次」的概念，識別、「本週」或「這週」（如「本週五」指的是本週的星期五）、「下週」（如「下週二」指的是下週的星期二)，並第1、8、9點計算出相應的日期(幾月幾日)
              5.定義一週的起始日是星期 1 (Monday)
              6.定義「周六」、「週六」，皆解釋為「星期六」在英文中是 Saturday，並根據第1、8點計算出相應的日期(幾月幾日)
              7.定義「星期日」、「週日」，皆解釋為「星期天」在英文中是 Sunday，並根據第1、8、9點計算出相應的日期(幾月幾日)
              8.星期六是星期一後的第 5 天
              9.星期天是 ${now.day + 7 - now.weekday} 號
              10.句子中如果出現「假日」、「周末」、「週末」是 ${now.day + 7 - now.weekday} 號
              須遵守規則如下：
              1.使用繁體中文輸出分析結果，結果為一個字串並以"："分隔
              2.日期格式為YYYY/MM/DD，時間格式為HH:mm:ss
              3.如果無法判斷輸入日期及時間，日期輸出默認為現在日期，開始時間輸出設定為08:00，結束時間設定為08:00
              4.如果無法從提供的句子中解析出行事曆事件。句子中如果不包含任何日期、時間或活動相關資訊。則輸出：辨識錯誤
              範例如下：
              輸入範例1:今天和老師有一個會議，時間為下午2點持續3個小時
              輸出範例1:行為：新增，日期：${now.year}/${now.month}/${now.day}，開始時間：14:00:00，結束時間：17:00:00，活動名稱：和老師開會
              輸入範例2:今天和老師開會
              輸出範例2:行為：新增，日期：${now.year}/${now.month}/${now.day}，開始時間：08:00:00，結束時間：08:00:00，活動名稱：和老師開會
              輸入範例3:今天和老師開會取消了
              輸出範例3:行為：刪除，日期：${now.year}/${now.month}/${now.day}，開始時間：08:00:00，結束時間：08:00:00，活動名稱：和老師開會
              輸入範例4:星期三要展示專案
              輸出範例4:行為：新增，日期：${now.year}/${now.month}/${now.day + 3 - now.weekday}，開始時間：08:00:00，結束時間：08:00:00，活動名稱：展示專案
              
              輸入句子為：$sentence''';

      final model = ChatGoogleGenerativeAI(
          apiKey: "AIzaSyA64LawC9SJL5I6PM0ZDQ2JhApEdF2ycpc");
      final prompt = PromptValue.string(inputString);
      final resultJson = await model.invoke(prompt);

      //print(inputString);
      //print("輸入句子為：$sentence");
      //print(resultJson.outputAsString);
      //print("");
      String outString = resultJson.outputAsString;
      print("原始句子 $sentence");
      print("解析後的句子 $outString");
      return outString;
    } catch(e){
      print("出現錯誤了： $e");
      return "錯誤";
    }
  }


  // @Line 通知
  final String lineNotifyUrl = 'https://notify-api.line.me/api/notify';// Line Notify 的 API 網址
  final String lineNotifyToken = 'HlLecrGzvTDaesIzcxDRh6l8QOnWs9XMujJU96JdkwD';// Line Notify 的權杖
  var emoID = ['\u2B55','\u274C','\u267B'];
  Future<void> _sendLineNotify(int state,String message) async {
    final headers = {
      'Authorization': 'Bearer $lineNotifyToken',
    };
    String emoji = emoID[state];
    String fullMessage = emoji + ' ' + message;
    Map<String, String> data = {
      'message': fullMessage,
    };

    try {
      final response = await http.post(
        Uri.parse(lineNotifyUrl),
        headers: headers,
        body: data,
      );

      // Log the response status and body
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('Line Notify sent successfully!');
      } else {
        print('Failed to send Line Notify. Status code: ${response.statusCode}');
      }
    } catch (e) {
      // print('Error sending Line Notify: $e');
      print("通知錯誤");
      _showErrorDialog(context, '通知錯誤','發送 Line Notify 時發生錯誤');
    }
  }


  @override
  void initState() {  // 初始化狀態，設置默認值和監聽器
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier(_getEventsForDay(_selectedDay!));  // 初始化選中日期的事件列表
  }

  @override
  void dispose() {  // 釋放資源，清理監聽器
    _selectedEvents.dispose();
    super.dispose();
  }

  // @選中日期改變狀態
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {  // 當選中日期改變時的回調函數
    if (!isSameDay(_selectedDay, selectedDay)) {  // 如果選中的日期和之前不同，則更新狀態
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedEvents.value = _getEventsForDay(selectedDay);  // 更新選中日期的事件列表
        _selectedEvents.notifyListeners(); // 通知 UI 更新
      });
    }
  }

  // @刪除對話框
  void _showDeleteConfirmationDialog(BuildContext context, Event event) {  // 顯示刪除確認對話框
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('刪除活動'),  // 對話框標題
          content: const Text('確認要刪除此活動?'),  // 對話框內容
          actions: <Widget>[  // 對話框操作按鈕
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();  // 取消刪除，關閉對話框
              },
              child: const Text('取消'),  // 取消按鈕
            ),
            TextButton(
              onPressed: () {
                int error = _deleteEvent(event);  // 確認刪除，調用刪除事件方法
                Navigator.of(context).pop();  // 關閉對話框
                _showErrorDialog(context, eState[error]!, error >= 0 ? "操作成功" : "請重新操作");
              },
              child: const Text('刪除'),  // 刪除按鈕
            ),
          ],
        );
      },
    );
  }

  // @事件操作-刪除方法
  int _deleteEvent(Event event) {  // 刪除事件的方法
    int error = 1;
    try {
      setState(() {
        events[_selectedDay!]!.remove(event); // 從事件列表中刪除指定事件
        _selectedEvents.value = _getEventsForDay(_selectedDay!); // 更新選中日期的事件列表
        _selectedEvents.notifyListeners(); // 通知 UI 更新
      });
    } catch (e){
      //print("刪除產生錯誤：$e");
      print("刪除產生錯誤");
      error =  -3;
    }
    _sendLineNotify(1, "\n刪除活動：${event.name} \n"
        "開始時間: ${event._formatTimeforLine(event.timeFrom)} \n"
        "結束時間: ${event._formatTimeforLine(event.timeTo)}");
    return error;
  }

  // @事件操作-新增方法
  int _addEvent() {  // 添加事件的方法
    final selectedDayEvents = events[_selectedDay];  // 獲取選中日期的事件列表
    int newId = selectedDayEvents?.isNotEmpty == true  // 新事件的唯一標識符
        ? selectedDayEvents!.last.id + 1
        : 0;

    final newEvent = Event(  // 創建新事件
      newId,
      _eventController.text,
      DateTime(
        _selectedDay!.year,
        _selectedDay!.month,
        _selectedDay!.day,
        _from.hour,
        _from.minute,
      ),
      DateTime(
        _selectedDay!.year,
        _selectedDay!.month,
        _selectedDay!.day,
        _to.hour,
        _to.minute,
      ),
    );


    // 錯誤偵測
    if (newEvent.timeFrom.isAfter(newEvent.timeTo)) {
      print("時間使用錯誤");  //時間設定錯誤提示
      return -21;
    }


    //事件加入動作
    if (selectedDayEvents != null) {
      selectedDayEvents.add(newEvent);  // 添加新事件到事件列表
    } else {
      events[_selectedDay!] = [newEvent];  // 如果日期沒有對應事件，則創建新的事件列表
    }
    _eventController.clear();  // 清空事件名稱輸入框
    _selectedEvents.value = _getEventsForDay(_selectedDay!);  // 更新選中日期的事件列表
    _selectedEvents.notifyListeners(); // 通知 UI 更新

    //Line 提示通知
    _sendLineNotify(0,"\n新增活動：${newEvent.name} \n"
        "開始時間: ${newEvent._formatTimeforLine(newEvent.timeFrom)} \n"
        "結束時間: ${newEvent._formatTimeforLine(newEvent.timeTo)}");
    return 0;
  }

  // @事件操作-編輯方法
  int _editEvent(Event event) {  // 編輯事件的方法
    int error = 2;
    final oldName = event.name;
    final oldFrom = event.timeFrom;
    final oldTo = event.timeTo;

    event.name = _eventController.text;  // 更新事件名稱
    event.timeFrom = DateTime(  // 更新開始時間
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
      _from.hour,
      _from.minute,
    );
    event.timeTo = DateTime(  // 更新結束時間
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
      _to.hour,
      _to.minute,
    );

    //錯誤偵測
    if (event.timeFrom.isAfter(event.timeTo)) {
      print("時間使用錯誤");  //時間設定錯誤提示
      error = -4;
      return error;
    }

    _selectedEvents.value = _getEventsForDay(_selectedDay!);  // 更新選中日期的事件列表
    _selectedEvents.notifyListeners(); // 通知 UI 更新

    _sendLineNotify(2,"\n編輯活動：${oldName} \n"
        "原本開始時間: ${event._formatTimeforLine(oldFrom)} \n"
        "原本結束時間: ${event._formatTimeforLine(oldTo)}\n"
        "新開始時間: ${event._formatTimeforLine(event.timeFrom)} \n"
        "新結束時間: ${event._formatTimeforLine(event.timeTo)}");
    return error;
  }

  // @事件操作-字串處理及NLP 此函數解析輸入的句子
  int _analysisSentence(String sentence) {
    print("開始解析輸入字串");
    // 用於存儲句子分析結果
    Map<String, String> parsedResult = {};
    // 用於儲存使用者輸入的日期及時間
    DateTime userDate;
    TimeOfDay formTime, toTime;

    // 儲存日期，時間
    int year = DateTime.now().year;
    int month = DateTime.now().month;
    int day = DateTime.now().day;
    int formHour = DateTime.now().hour;
    int formMin = DateTime.now().minute;
    int toHour = DateTime.now().hour;
    int toMin = DateTime.now().minute;

    try {
      // 解析句子中的參數
      List<String> components = sentence.split('，');
      for (var component in components) {
        List<String> keyValue = component.split('：');
        if (keyValue.length == 2) {
          parsedResult[keyValue[0].trim()] = keyValue[1].trim();
        }
      }

      // 分析使用者輸入的日期
      List<String> dateParts = parsedResult['日期']?.split('/') ?? [];
      switch (dateParts.length) {
        case 3:
          year = int.parse(dateParts[0]);
          month = int.parse(dateParts[1]);
          day = int.parse(dateParts[2]);
          break;
        case 2:
          month = int.parse(dateParts[0]);
          day = int.parse(dateParts[1]);
          break;
        case 1:
          day = int.parse(dateParts[0]);
          break;
        default:
          print("date error");
          return -1;
      }

      // 分析使用者輸入的開始時間
      List<String> formTimeParts = parsedResult['開始時間']?.split(':') ?? [];
      switch (formTimeParts.length) {
        case 3:
        case 2:
          formHour = int.parse(formTimeParts[0]);
          formMin = int.parse(formTimeParts[1]);
          break;
        case 1:
          formHour = int.parse(formTimeParts[0]);
          break;
        default:
          print("start time error");
          return -1;
      }

      // 分析使用者輸入的結束時間
      List<String> toTimeParts = parsedResult['結束時間']?.split(':') ?? [];
      switch (toTimeParts.length) {
        case 3:
        case 2:
          toHour = int.parse(toTimeParts[0]);
          toMin = int.parse(toTimeParts[1]);
          break;
        case 1:
          toHour = int.parse(toTimeParts[0]);
          break;
        default:
          print("end time error");
          return -1;
      }

      // 使用者輸入的日期
      userDate = DateTime.utc(year, month, day, 0, 0, 0);
      formTime = TimeOfDay(hour: formHour, minute: formMin);
      toTime = TimeOfDay(hour: toHour, minute: toMin);

      // 更新使用者所選擇的日期
      _onDaySelected(userDate, userDate);
      _selectedDay = userDate;
      _focusedDay = userDate;
      _from = formTime;
      _to = toTime;

      // 判斷操作方式
      if (parsedResult['行為'] == '刪除') {
        List<Event> selectDayEventList = _getEventsForDay(_selectedDay!);
        for (int i = 0; i < selectDayEventList.length; i++) {
          if (parsedResult['活動名稱']?.compareTo(selectDayEventList[i].name) == 0) {
            _deleteEvent(selectDayEventList[i]);
            print("刪除成功");
            return 1;
          }
        }
        print("刪除失敗，該天找不到此名稱活動");
        return -3;
      } else if (parsedResult['行為'] == '新增') {
        _eventController.text = parsedResult['活動名稱']!;
        int error = _addEvent();
        print("新增");
        print(_getEventsForDay(_selectedDay!));
        return error;
      } else {
        print("操作錯誤");
        return -1;
      }
    } catch (e) {
      //print('Error text input: $e');
      print("句子解析錯誤");
      return -1;
    }
  }

  //  @添加和編輯對話框
  void _showAddEditEventDialog({Event? event}) {  // 顯示添加或編輯事件的對話框
    bool isEditing = event != null;  // 是否是編輯模式
    _eventController.text = event?.name ?? '';  // 如果是編輯模式，填充事件名稱

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              scrollable: true,
              title: Text(isEditing ? "編輯活動" : "新增活動"),  // 對話框標題，根據編輯模式顯示不同文本
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _eventController,
                    decoration: const InputDecoration(labelText: '事件名稱'),  // 事件名稱輸入框
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: Text('選擇開始時間：${_from.format(context)}'),  // 選擇開始時間的列表項
                    onTap: () async {
                      final newTime = await showTimePicker(
                        context: context,
                        initialTime: _from,
                      );  // 調用时間選擇器
                      if (newTime != null) {
                        setState(() {
                          _from = newTime;  // 更新開始時間
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text('選擇結束時間：${_to.format(context)}'),  // 選擇結束時間的列表項
                    onTap: () async {
                      final newTime = await showTimePicker(
                        context: context,
                        initialTime: _to,
                      );  // 調用时間選擇器
                      if (newTime != null) {
                        setState(() {
                          _to = newTime;  // 更新結束時間
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      int error = 0;
                      if (isEditing) {
                        error = _editEvent(event);  // 保存修改事件
                      } else {
                        error = _addEvent();  // 提交新事件
                      }
                      _eventController.clear();
                      Navigator.of(context).pop();  // 關閉對話框
                      _showErrorDialog(context, eState[error]!, error >= 0 ? "操作成功" : "${eState[error]}，請重新設定");
                    });
                  },
                  child: Text(isEditing ? "保存修改" : "提交"),  // 操作按鈕文本，根據編輯模式顯示不同文本
                )
              ],
            );
          },
        );
      },
    );
  }

  List<Event> _getEventsForDay(DateTime day) {  // 獲取指定日期的事件列表
    return events[day] ?? [];  // 返回指定日期的事件列表，如果沒有則返回空列表
  }

  //  @主畫面-主要建構樹
  @override
  Widget build(BuildContext context) {  // 構建小部件樹
    return Scaffold(  // 返回Scaffold小部件，用於構建基本的應用程序頁面
      appBar: AppBar(  // 應用程序欄
        title: const Text("我的日曆"),  // 標題文字
        actions: [
          IconButton(
              icon: const Icon(
                Icons.pets,
                color: Colors.black,
              ),
              onPressed: () {
                print('按下狗掌');
                _showErrorDialog(context, "你好~~", "今天是${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}");
                _onDaySelected(DateTime.now(), DateTime.now());
                print(_selectedDay);
              }
          ),
          IconButton(
            icon: const Icon(
              Icons.textsms_outlined,
              color: Colors.black,
            ),
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (context){
                    return AlertDialog(
                      scrollable: true,
                      title: const Text("文字新增活動"),
                      content: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextField(
                          decoration: const InputDecoration(
                              labelText: "請輸入一段文字，須包含日期活動內容\n"
                                  "輸入完後須稍等一下。"
                          ),
                          controller: _eventController,
                        ),
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () async {
                            _nlpString = await _nlpAnalyze(_eventController.text);  // NLP判斷使用者想法
                            _eventController.clear();
                            Navigator.of(context).pop();  // 關閉對話框
                            setState(() {
                              int error = _analysisSentence(_nlpString);  //  字串處理新增
                              // print(error);
                              _nlpString = "";
                              _showErrorDialog(context, eState[error]!, error >= 0 ? "操作成功" : "請重新操作");
                            });
                          },
                          child: const Text("提交"), // 按鈕上的文本為 "提交"
                        )
                      ],
                    );
                  });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(  // 浮動操作按鈕，用於添加新事件
        onPressed: () {
          _showAddEditEventDialog();  // 點擊時顯示添加或編輯事件的對話框
        },
        child: const Icon(Icons.add),  // 按鈕圖標
      ),
      body: Column(  // 列布局，包含日曆和事件列表
        children: [
          TableCalendar(  // 表格日曆小部件
            rowHeight: 43,  // 日曆行高度
            headerStyle: const HeaderStyle(  // 日曆頭部樣式
              formatButtonVisible: true,  // 顯示格式切換按鈕
              titleCentered: true,  // 標題居中顯示
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(  // 星期標題樣式
              weekdayStyle: TextStyle(color: Colors.green),  // 工作日文字顏色
              weekendStyle: TextStyle(color: Colors.red),  // 週末文字顏色
            ),
            availableGestures: AvailableGestures.all,  // 可用手勢：所有手勢
            calendarFormat: _calendarFormat,  // 日曆格式
            selectedDayPredicate: (day) => isSameDay(day, _focusedDay),  // 選中日期的預測方法
            focusedDay: _focusedDay,  // 聚焦日期
            firstDay: DateTime.utc(2000, 1, 1),  // 日曆可選的第一天
            lastDay: DateTime.utc(2050, 1, 1),  // 日曆可選的最後一天
            onDaySelected: _onDaySelected,  // 選中日期時的回調函數
            eventLoader: _getEventsForDay,  // 加載事件的方法
            calendarStyle: const CalendarStyle(  // 日曆樣式
              outsideDaysVisible: false,  // 不顯示非當月日期
            ),
            onFormatChanged: (format) {  // 格式變更時的回調函數
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;  // 更新日曆格式
                });
              }
            },
            onPageChanged: (focusedDay) {  // 日曆翻頁時的回調函數
              _focusedDay = focusedDay;  // 更新聚焦日期
            },
          ),
          const SizedBox(height: 8.0),  // 間距
          Expanded(  // 擴展小部件，填充剩餘空間
            child: ValueListenableBuilder<List<Event>>(  // 根據監聽的值動態構建小部件
              valueListenable: _selectedEvents,  // 監聽選中日期的事件列表
              builder: (context, value, _) {
                return ListView.builder(  // 構建事件列表
                  itemCount: value.length,  // 事件數量
                  itemBuilder: (context, index) {
                    return Container(  // 容器
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),  // 邊距
                      decoration: BoxDecoration(  // 裝飾
                        border: Border.all(),  // 邊框
                        borderRadius: BorderRadius.circular(12),  // 圓角
                      ),
                      child: ListTile(  // 列表項
                        onTap: () {  // 點擊事件
                          _showAddEditEventDialog(event: value[index]);  // 顯示編輯對話框
                        },
                        title: Text("${value[index]}"),  // 事件描述
                        trailing: IconButton(  // 列表尾部圖標按鈕
                          icon: const Icon(Icons.delete),  // 刪除圖標
                          onPressed: () {
                            _showDeleteConfirmationDialog(context, value[index]);  // 點擊時顯示刪除對話框
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}