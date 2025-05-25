## **一、存储过程和触发器实验**

### （一）存储过程

#### **多表查询：余票查询**

1. 存储逻辑代码

   ```sql
   -- 余票查询
   DELIMITER //
   CREATE PROCEDURE QueryAvailableTickets(
       IN p_depart_date DATE,
       IN p_from_station VARCHAR(50),
       IN p_to_station VARCHAR(50)
   )
   BEGIN
       SELECT t.TrainID, tk.DepartureDate, st.TypeName, 
              ts_from.DepartureTime, ts_to.ArrivalTime,
              tk.AvailableCount, tk.Price
       FROM Tickets tk
       JOIN Trains t ON tk.TrainID = t.TrainID
       JOIN SeatTypes st ON tk.SeatTypeID = st.SeatTypeID
       -- 关联出发站停靠点及车站名称
       JOIN TrainStops ts_from ON (tk.TrainID = ts_from.TrainID AND tk.FromStationID = ts_from.StationID)
       JOIN Stations s_from ON ts_from.StationID = s_from.StationID
       -- 关联到达站停靠点及车站名称
       JOIN TrainStops ts_to ON (tk.TrainID = ts_to.TrainID AND tk.ToStationID = ts_to.StationID)
       JOIN Stations s_to ON ts_to.StationID = s_to.StationID
       WHERE tk.DepartureDate = p_depart_date
         AND ts_from.StopOrder < ts_to.StopOrder  -- 确保出发站在前
         AND tk.AvailableCount > 0
         AND s_from.StationName = p_from_station  -- 验证出发站名称
         AND s_to.StationName = p_to_station;     -- 验证到达站名称
   END //
   DELIMITER ;
   ```

   - 输入日期、起点站、到达站即可查询当日两地之间的车票。

2. 存储过程验证

   ```sql
   CALL QueryAvailableTickets('2025-04-05', '北京西站', '上海虹桥');
   ```

   ![image-20250523194757881](.\image\image-20250523194757881.png)

#### 数据插入：订票操作

1. 存储逻辑代码

   ```sql
   -- 订单插入与余票扣减存储过程【省略部分代码】
   DELIMITER //
   CREATE PROCEDURE CreateOrder(
       IN p_user_id INT,
       IN p_train_id VARCHAR(10),
       IN p_depart_date DATE,
       IN p_seat_type_id INT,
       IN p_ticket_count INT
   )
   BEGIN
       DECLARE v_available INT;
       DECLARE v_ticketid BIGINT;
       DECLARE v_price DECIMAL(10,2);
       DECLARE v_order_id BIGINT;  -- 新增变量存储生成的订单ID
       
       START TRANSACTION;
       
       -- 获取余票和价格
       
       IF v_available >= p_ticket_count THEN
           -- 插入订单（自动生成OrderID）
           INSERT INTO Orders (UserID, TotalAmount, Status) 
           VALUES (p_user_id, v_price * p_ticket_count, '待支付');
           
           -- 获取自增的OrderID
           SET v_order_id = LAST_INSERT_ID();
           
           -- 插入订单详情（修正UnitPrice为单价）
           INSERT INTO OrderDetails 
             (OrderID, TicketID, SeatTypeID, Quantity, UnitPrice)
           VALUES 
             (v_order_id, v_ticketid, p_seat_type_id, p_ticket_count, v_price);
           
           -- 更新余票数量
           
           COMMIT;
       ELSE
           ROLLBACK;
           SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = '余票不足';
       END IF;
   END //
   DELIMITER ;
   ```
   
   - 输入用户ID、车次、日期、座位等级、票数即可完成订票，且订单信息状态为`待支付`。
   
2. 存储过程验证

   1. 余票充足时：

      ```sql
      CALL Createorder(1, 'G101', '2025-04-05', 3, 2);
      ```

      ![terminal](.\image\image-20250516012441439.png)

      ![order](.\image\image-20250516012422186.png)

      ![orderdetails](.\image\image-20250516012404068.png)

   2. 余票不足时：

      ```sql
      CALL Createorder(1, 'G101', '2025-04-05', 3, 2000);
      ```

      ![short of tickets](C:\Users\steven\Pictures\Screenshots\屏幕截图 2025-05-16 012529.png)

#### 数据删除：取消订单

1. 存储逻辑代码

   ```sql
   -- 数据删除存储过程
   DELIMITER //
   CREATE PROCEDURE CancelOrder(IN p_order_id BIGINT)
   BEGIN
       DECLARE EXIT HANDLER FOR SQLEXCEPTION
       BEGIN
           ROLLBACK;
           RESIGNAL;
       END;
   
       START TRANSACTION;
   
       -- 验证订单是否存在且未支付（根据业务需求调整状态条件）
       IF NOT EXISTS (
           SELECT 1 FROM Orders 
           WHERE OrderID = p_order_id 
             AND Status = '待支付'  -- 仅允许取消待支付订单
       ) THEN
           SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = '订单不可取消';
       END IF;
   
       -- 标记订单为已取消
       UPDATE Orders 
       SET Status = '已取消',
          -- PaymentTime = NULL,
          -- PaymentMethod = NULL
       WHERE OrderID = p_order_id;
   
       -- 恢复余票
       UPDATE Tickets t
       JOIN OrderDetails od ON t.TicketID = od.TicketID
       SET t.AvailableCount = t.AvailableCount + od.Quantity
       WHERE od.OrderID = p_order_id
         AND t.AvailableCount + od.Quantity <= t.TotalCount;  -- 防止超库存
   
       COMMIT;
   END //
   DELIMITER ;
   ```

   - 输入订单ID即可完成订单取消，但前提是订单为待支付状态。

2. 存储过程验证

   1. 待支付订单可以取消：

      ```sql
      CALL CancelOrder(6);
      ```

      ![terminal](.\image\image-20250516012814356.png)

      ![order](.\image\image-20250516012657290.png)

   2. 其他订单不可直接取消：

      ```sql
      CALL CancelOrder(1);
      ```

      ![image-20250516012751672](.\image\image-20250516012751672.png)

#### 数据修改：车票改签

1. 存储逻辑代码

   ```sql
   -- 改签操作【省略部分代码】
   DELIMITER //
   CREATE PROCEDURE ChangeTicket(
       IN p_order_id BIGINT,
       IN p_new_train_id VARCHAR(10),
       IN p_new_depart_date DATE,
       IN p_new_seat_type_id INT,
       IN p_ticket_count INT
   )
   BEGIN
       DECLARE v_old_ticket_id BIGINT;
       DECLARE v_old_price DECIMAL(10,2);
       DECLARE v_new_price DECIMAL(10,2);
       DECLARE v_new_ticket_id BIGINT;
       DECLARE v_available INT;
       DECLARE v_total_amount DECIMAL(10,2);
       
       -- 异常处理
       -- 验证原订单有效性
       -- 获取原票信息（假设单票种改签）
       -- 获取新票信息并锁定
       -- 检查新票余量
       
       -- 扣减新票余量
       UPDATE Tickets
       SET AvailableCount = AvailableCount - p_ticket_count
       WHERE TicketID = v_new_ticket_id;
   
       -- 计算差额金额（可根据业务调整）
       SET v_total_amount = (v_new_price * p_ticket_count) - (v_old_price * p_ticket_count);
   
       -- 更新订单信息
       UPDATE Orders
       SET TotalAmount = TotalAmount + v_total_amount,
           Status = '已改签'
       WHERE OrderID = p_order_id;
   
       -- 更新订单详情
       UPDATE OrderDetails
       SET TicketID = v_new_ticket_id,
           SeatTypeID = p_new_seat_type_id,
           Quantity = p_ticket_count,
           UnitPrice = v_new_price
       WHERE OrderID = p_order_id;
   
       COMMIT;
   END //
   DELIMITER ;
   ```
   
   - 输入订单ID、改签新车次、改签新日期、座位等级和票数即可完成改签操作，但前提是订单已支付。
   
2. 存储过程验证

   1. 仅已支付订单可以改签

      ```sql
      CALL ChangeTicket(3, 'G101', '2025-04-05', 2, 1);
      ```

      ![terminal](.\image\image-20250516112440675.png)

      ![order](.\image\image-20250516112400892.png)

      ![orderdetails](.\image\image-20250516112422626.png)

   2. 已完成订单和待支付订单无法改签

      ```sql
      CALL ChangeTicket(3, 'G101', '2025-04-05', 2, 2);
      ```

      ![terminal](.\image\image-20250516012946855.png)

### **（二）前端调用后台存储程序**

#### 概述 (前端`b/s`+后端`Pythonflask`)

1. 设计思路

   - 使用`mysql.connector`库实现`Python`程序`app.py`与`MySQL`数据库的连接；

   - 使用`Python`的`Flask`框架进行后端的搭建；

   - 使用`html`+`css`+`js`进行`b/s`架构的`test.html`前端搭建。

2. 后端命令行：![image-20250525001944609](.\image\image-20250525001944609.png)

3. 前端余票查询界面：![image-20250525002037703](.\image\image-20250525002037703.png)

   ![image-20250525002111704](.\image\image-20250525002111704.png)

#### 余票查询 (`/api/query_tickets`)

1. 查询代码

   ```python
   # 查询余票【省略部分代码】
   @app.route('/api/query_tickets', methods=['POST'])
   def query_tickets():
       data = request.get_json()
       try:
           cursor = conn.cursor(dictionary=True)
           
           # 调用存储过程
           cursor.callproc('QueryAvailableTickets', (depart_date, from_station, to_station))
           
           # 获取存储过程结果
           tickets = []
           for result in cursor.stored_results():
               rows = result.fetchall()
               logger.info(f"获取到 {len(rows)} 条车票记录")
               
               for row in rows:
                   # 转换数据类型确保JSON可序列化
                   # 处理DepartureDate
                   # 处理timedelta类型的时间
                   if 'DepartureTime' in row and isinstance(row['DepartureTime'], timedelta):  # 使用直接导入的timedelta
                       # 将timedelta转换为HH:MM格式字符串
                   
                   if 'ArrivalTime' in row and isinstance(row['ArrivalTime'], timedelta):  # 使用直接导入的timedelta
                       # 将timedelta转换为HH:MM格式字符串
                   
                   tickets.append(row)
           
           logger.info(f"处理后车票数据示例: {tickets[:1]}")
           
           if not tickets:
               return jsonify({'success': True, 'data': [], 'message': '未查询到符合条件的车票'})
           
           return jsonify({'success': True, 'data': tickets})
       
       finally:
           if conn and conn.is_connected():
               cursor.close()
               conn.close()
   ```

2. 程序功能

   - 通过POST请求接收出发日期、出发站和到达站参数
   - 调用MySQL存储过程`QueryAvailableTickets`查询符合条件的车票
   - 处理数据库返回的复杂数据类型（如时间差、日期、价格等）
   - 返回包含车次、座位类型、余票数量、价格等信息的列表

3. 测试效果

   1. 后端界面

      ![image-20250525003409729](.\image\image-20250525003409729.png)

   2. 前端界面

      ![image-20250525003313843](.\image\image-20250525003313843.png)

#### 订票操作 (`/api/create_order`)

1. 订票代码

   ```python
   # 创建订单【省略部分代码】
   @app.route('/api/create_order', methods=['POST'])
   def create_order():
       data = request.get_json()
       try:
           cursor = conn.cursor(dictionary=True)
           
           # 记录请求参数
           logger.info(f"创建订单请求参数: {data}")
           
           # 调用存储过程
           cursor.callproc('CreateOrder', (
               data['user_id'],
               data['train_id'],
               data['depart_date'],
               data['seat_type_id'],
               data['ticket_count']
           ))
           
           # 获取存储过程输出
           order_result = None
           for result in cursor.stored_results():
               order_result = result.fetchone()
               logger.info(f"存储过程返回结果: {order_result}")
               break  # 只取第一个结果集
           
           # 检查订单是否创建成功
           if order_result and 'order_id' in order_result:
               # 转换数据类型
           
           # 如果没有返回order_id，但数据库已更新
           conn.commit()  # 确保提交事务
           logger.warning("存储过程未返回order_id，但数据库可能已更新")
           
           # 尝试从数据库查询最新订单
           # ...
           if latest_order:
               logger.info(f"从数据库查询到最新订单: {latest_order}")
               return jsonify({
                   'success': True,
                   'message': '订单创建成功(从数据库确认)',
                   'order_id': latest_order['order_id'],
                   'total_amount': float(latest_order['total_amount']),
                   'status': latest_order['Status']
               })
   
       finally:
           if conn and conn.is_connected():
               cursor.close()
               conn.close()
   ```

2. 程序功能

   - 接收用户ID、车次ID、出发日期、座位类型和票数等参数
   - 调用存储过程`CreateOrder`完成原子性订票操作
   - 双重确认机制：优先使用存储过程返回的订单ID，失败时主动查询最新订单

3. 测试效果

   1. 后端界面

      ![image-20250525003539788](.\image\image-20250525003539788.png)

   2. 前端界面

      ![image-20250525003502791](.\image\image-20250525003502791.png)

      ![image-20250525003612146](.\image\image-20250525003612146.png)

#### 取消订单 (`/api/create_order`)

1. 取消代码

   ```python
   # 取消订单
   @app.route('/api/cancel_order', methods=['POST'])
   def cancel_order():
       data = request.get_json()
       if not data or 'order_id' not in data:
           return jsonify({'success': False, 'error': '缺少order_id'}), 400
   
       conn = get_db_connection()
       if not conn:
           return jsonify({'success': False, 'error': '数据库连接失败'}), 500
   
       try:
           cursor = conn.cursor(dictionary=True)
           
           # 调用存储过程取消订单
           cursor.callproc('CancelOrder', (data['order_id'],))
           
           conn.commit()
           
           return jsonify({
               'success': True,
               'message': '订单取消成功'
           })
       except Error as e:
           conn.rollback()
           logger.error(f"取消订单错误: {e}")
           return jsonify({'success': False, 'error': str(e)}), 500
       finally:
           if conn and conn.is_connected():
               cursor.close()
               conn.close()
   ```

2. 程序功能

   - 通过订单ID取消未支付的订单
   - 调用存储过程`CancelOrder`处理取消逻辑
   - 立即释放相关票务资源

3. 测试效果

   1. 后端界面

      ![image-20250525003856759](.\image\image-20250525003856759.png)

   2. 前端界面

      ![image-20250525003718385](.\image\image-20250525003718385.png)

      ![image-20250525003913900](.\image\image-20250525003913900.png)

#### 车票改签 (`/api/create_order`)

1. 改签代码

   ```python
   # 车票改签【省略部分代码】
   @app.route('/api/change_ticket', methods=['POST'])
   def change_ticket():
       data = request.get_json()
       
       # 检查必要字段
       required_fields = {
           'order_id': '订单ID',
           'new_train_id': '新车次ID',
           'new_depart_date': '新出发日期',
           'new_seat_type_id': '新座位类型',
           'new_ticket_count': '新票数'
       }
       
       missing_fields = [field for field in required_fields if field not in data]
       if missing_fields:
           return jsonify({
               'success': False,
               'error': '缺少必要字段',
               'missing_fields': [required_fields[field] for field in missing_fields]
           }), 400
       
       # 验证新车次ID不为空
           
       try:
           cursor = conn.cursor(dictionary=True)
   
           # 调用存储过程
           cursor.callproc('ChangeTicket', (
               data['order_id'],
               data['new_train_id'],
               data['new_depart_date'],
               data['new_seat_type_id'],
               int(data['new_ticket_count'])  # 确保是整数
           ))
               
           conn.commit()
           return jsonify({
               'success': True, 
               'message': '改签成功',
           })
           
       finally:
           if conn and conn.is_connected():
               cursor.close()
               conn.close()
   ```

2. 程序功能

   - 支持订单改签到新车次/新日期/新座位类型

   - 调用存储过程`ChangeTicket`原子性完成：

     - 原订单取消

     - 新票务资源分配

     - 订单更新

3. 测试效果

   1. 后端界面

      ![image-20250525004249430](.\image\image-20250525004249430.png)

   2. 前端界面

      ![image-20250525004028151](.\image\image-20250525004028151.png)

### **（三）触发器**

#### 数据插入：记录新用户注册日志

1. 触发器代码

   ```sql
   -- 创建AFTER INSERT触发器
   DELIMITER //
   CREATE TRIGGER after_user_insert
   AFTER INSERT ON Users
   FOR EACH ROW
   BEGIN
       INSERT INTO UserRegistrationLogs (UserID, Username, RegisterTime)
       VALUES (NEW.UserID, NEW.Username, NEW.RegisterTime);
   END //
   DELIMITER ;
   ```
   
2. 测试效果

   ```sql
   INSERT INTO Users (Username, PASSWORD, RealName, IDCard, Phone, Email, Gender)
   VALUES ('trigger_test', 'e10adc3949ba59abbe56e057f20f883e', '触发器测试', '110101199007071240', '13800138007', 'trigger@example.com', 0);
   SELECT * FROM UserRegistrationLogs WHERE Username = 'trigger_test';
   ```

   ![image-20250523185311581](.\image\image-20250523185311581.png)

#### 数据更新：车次状态变更审计

1. 触发器代码

   ```sql
   -- 创建BEFORE UPDATE触发器
   DELIMITER //
   CREATE TRIGGER before_train_update
   BEFORE UPDATE ON Trains
   FOR EACH ROW
   BEGIN
       IF OLD.IsActive <> NEW.IsActive THEN
           INSERT INTO TrainStatusAudit (TrainID, OldStatus, NewStatus, ChangedBy)
           VALUES (OLD.TrainID, OLD.IsActive, NEW.IsActive, CURRENT_USER());
       END IF;
   END //
   DELIMITER ;
   ```
   
2. 测试效果

   ```SQL
   SELECT TrainID, IsActive FROM Trains WHERE TrainID = 'G201';
   UPDATE Trains SET IsActive = FALSE WHERE TrainID = 'G201';
   SELECT * FROM TrainStatusAudit WHERE TrainID = 'G201';
   ```

   ![image-20250523185356862](.\image\image-20250523185356862.png)

#### 数据删除：订单删除备份

1. 触发器代码

   ```sql
   -- 创建BEFORE DELETE触发器
   DELIMITER //
   CREATE TRIGGER before_order_delete
   BEFORE DELETE ON Orders
   FOR EACH ROW
   BEGIN
       INSERT INTO DeletedOrdersBackup (OrderID, UserID, OrderTime, TotalAmount, STATUS, DeletedBy)
       VALUES (OLD.OrderID, OLD.UserID, OLD.OrderTime, OLD.TotalAmount, OLD.STATUS, CURRENT_USER());
   END //
   DELIMITER ;
   ```
   
2. 测试效果

   ```SQL
   INSERT INTO Orders (UserID, TotalAmount, STATUS) VALUES (2, 200.00, '待测试');
   SET @test_order = LAST_INSERT_ID();
   DELETE FROM Orders WHERE OrderID = @test_order;
   SELECT * FROM DeletedOrdersBackup WHERE OrderID = @test_order;
   ```

   ![image-20250523185608835](.\image\image-20250523185608835.png)

------

## **二、索引实验**

### **（一）程序代码设计**

#### 无索引查询

```python
def query_without_index(idcard, repeat=10):
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        # 确保没有IDCard索引
        cursor.execute("SHOW INDEX FROM Users WHERE Column_name = 'IDCard'")
        if cursor.fetchone():
            cursor.execute("DROP INDEX IDCard ON Users")
            conn.commit()
        
        query_sql = "SELECT * FROM Users WHERE IDCard = %s"
        
        # 预热并确保查询有效
        cursor.execute(query_sql, (idcard,))
        result = cursor.fetchall()
        if not result:
            raise ValueError("测试IDCard不存在于数据库中")
        
        # 正式测试
        start_time = time.time()
        for _ in range(repeat):
            cursor.execute(query_sql, (idcard,))
            cursor.fetchall()  # 确保读取所有结果
        end_time = time.time()
        
        avg_time = (end_time - start_time) / repeat
        
        cursor.close()
        conn.close()
        return avg_time
    except Exception as e:
        print(f"无索引查询时出错: {e}")
        raise
```

#### 有索引查询

```python
def query_with_index(idcard, repeat=10):
    """有索引查询测试"""
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        # 确保有IDCard索引
        cursor.execute("SHOW INDEX FROM Users WHERE Column_name = 'IDCard'")
        if not cursor.fetchone():
            cursor.execute("CREATE INDEX IDCard ON Users (IDCard)")
            conn.commit()
        
        query_sql = "SELECT * FROM Users WHERE IDCard = %s"
        
        # 预热并确保查询有效
        cursor.execute(query_sql, (idcard,))
        result = cursor.fetchall()
        if not result:
            raise ValueError("测试IDCard不存在于数据库中")
        
        # 正式测试
        start_time = time.time()
        for _ in range(repeat):
            cursor.execute(query_sql, (idcard,))
            cursor.fetchall()  # 确保读取所有结果
        end_time = time.time()
        
        avg_time = (end_time - start_time) / repeat
        
        cursor.close()
        conn.close()
        return avg_time
    except Exception as e:
        print(f"有索引查询时出错: {e}")
        raise
```

### **（二）数据分析**

#### 数据可视化

1. `experiment_results_large.csv`所存数据：

| data_size | insert_time | query_without_index | query_with_index |
| :-------: | :---------: | :-----------------: | :--------------: |
|    100    | 0.01750803  |     0.001007199     |    0.00084331    |
|   1000    | 0.105396748 |     0.002713394     |   0.000689745    |
|   5000    | 0.518647671 |     0.007108402     |   0.000702262    |
|   10000   | 0.825701952 |     0.012587929     |   0.000878167    |
|   50000   | 3.743389368 |     0.057782722     |   0.000811505    |
|  100000   | 6.951353312 |     0.111144686     |   0.000810361    |
|  1000000  | 74.25061369 |     1.681229639     |   0.000719953    |

2. 根据表格数据画图：

   ![index_performance_comparison_large](C:\Users\steven\Desktop\2025-2026春季学期\数据库\6-数据库第六次作业\index_performance_comparison_large.png)

#### 结果分析

1. 索引对查询性能的影响（核心结论）

|  数据量   | 无索引查询时间(秒) | 有索引查询时间(秒) | 性能提升倍数 |
| :-------: | :----------------: | :----------------: | :----------: |
|    100    |       0.0010       |       0.0008       |     1.2x     |
|  100,000  |       0.1111       |       0.0008       |     139x     |
| 1,000,000 |       1.6812       |       0.0007       |    2401x     |

- 结论：

  1. 随着数据量增加，索引的优势呈指数级增长

  2. 在百万级数据时，索引查询比无索引快2400倍

  3. 有索引时查询时间基本稳定在0.0007-0.0008秒，与数据量无关（O(1)复杂度）

  4. 无索引查询时间随数据量线性增长（O(n)复杂度）

2. 数据插入性能分析

|  数据量   | 插入时间(秒) | 单条平均插入时间(ms) |
| :-------: | :----------: | :------------------: |
|    100    |    0.0175    |        0.175         |
|   1,000   |    0.1054    |        0.105         |
|  100,000  |    6.9514    |        0.069         |
| 1,000,000 |    74.25     |        0.074         |

- 结论：

  1. 插入时间与数据量基本呈线性关系

  2. 批量插入优化效果明显（单条插入时间稳定在0.07ms左右）

  3. 百万数据插入约需74秒，属于合理范围

3. 理论验证

   - 无索引：全表扫描，时间复杂度O(n)： $T_{query} = k \times n $

   - 有索引：B+树查找，时间复杂度O(log n) → 实际近似O(1) ：$T_{query} = c $

   - 实测中索引查询时间基本恒定，与理论一致

------

## **三、附件**

1. [附件一：后端程序源代码`app.py`](./app.py)

2. [附件二：前端程序源代码`test.html`](./test.html)

3. [附件三：索引实验源代码`index.ipynb`](./index.ipynb) 
