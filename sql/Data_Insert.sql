-- 首先填充座位类型表（SeatTypes）
INSERT INTO SeatTypes (TypeName, Description)
VALUES
('商务座', '豪华座椅，提供优质服务'),
('一等座', '宽敞舒适的一等车厢座位'),
('二等座', '标准经济型座位'),
('硬卧', '普通卧铺车厢'),
('硬座', '普通座位车厢'),
('软卧', '高级卧铺车厢'),
('高级软卧', '豪华卧铺车厢'),
('特等座', '最高级别的座位');

-- 填充车站表（Stations）
INSERT INTO Stations (StationName, StationCode, City, Province)
VALUES
('北京西站', 'BXP', '北京', '北京市'),
('上海虹桥', 'SHH', '上海', '上海市'),
('广州南站', 'GZQ', '广州', '广东省'),
('深圳北站', 'SZQ', '深圳', '广东省'),
('武汉站', 'WHN', '武汉', '湖北省'),
('成都东站', 'CDW', '成都', '四川省'),
('西安北站', 'EAY', '西安', '陕西省'),
('南京南站', 'NJH', '南京', '江苏省'),
('杭州东站', 'HGH', '杭州', '浙江省'),
('长沙南站', 'CWQ', '长沙', '湖南省');

-- 填充用户表（Users）
INSERT INTO Users (Username, PASSWORD, RealName, IDCard, Phone, Email, Gender)
VALUES
('zhangsan', 'e10adc3949ba59abbe56e057f20f883e', '张三', '110101199001011234', '13800138001', 'zhangsan@example.com', 1),
('lisi', 'e10adc3949ba59abbe56e057f20f883e', '李四', '110101199002021235', '13800138002', 'lisi@example.com', 0),
('wangwu', 'e10adc3949ba59abbe56e057f20f883e', '王五', '110101199003031236', '13800138003', 'wangwu@example.com', 1),
('zhaoliu', 'e10adc3949ba59abbe56e057f20f883e', '赵六', '110101199004041237', '13800138004', 'zhaoliu@example.com', 0),
('qianqi', 'e10adc3949ba59abbe56e057f20f883e', '钱七', '110101199005051238', '13800138005', 'qianqi@example.com', 1);

-- 填充车次表（Trains）
INSERT INTO Trains (TrainID, TrainType, StartStation, EndStation, DepartureTime, ArrivalTime, Duration)
VALUES
('G101', '高铁', '北京西站', '上海虹桥', '07:00:00', '12:30:00', 330),
('G201', '高铁', '广州南站', '深圳北站', '08:30:00', '09:15:00', 45),
('D301', '动车', '武汉站', '成都东站', '09:00:00', '15:30:00', 390),
('G401', '高铁', '西安北站', '南京南站', '10:00:00', '15:45:00', 345),
('G501', '高铁', '杭州东站', '长沙南站', '11:30:00', '15:00:00', 210);

-- 填充车次-车站关联表（TrainStops）
INSERT INTO TrainStops (TrainID, StationID, ArrivalTime, DepartureTime, StopOrder, Distance)
VALUES
-- G101次列车停靠站
('G101', 1, NULL, '07:00:00', 1, 0),
('G101', 3, '09:30:00', '09:33:00', 2, 300),
('G101', 5, '11:00:00', '11:03:00', 3, 600),
('G101', 2, '12:30:00', NULL, 4, 1200),
-- G201次列车停靠站
('G201', 3, NULL, '08:30:00', 1, 0),
('G201', 4, '09:15:00', NULL, 2, 150),
-- D301次列车停靠站
('D301', 5, NULL, '09:00:00', 1, 0),
('D301', 7, '12:30:00', '12:33:00', 2, 450),
('D301', 6, '15:30:00', NULL, 3, 800);

-- 填充余票表（Tickets） - 更新了SeatTypeID与SeatTypes表对应
INSERT INTO Tickets (TrainID, DepartureDate, FromStationID, ToStationID, SeatTypeID, TotalCount, AvailableCount, Price)
VALUES
-- G101次2025-04-05余票
('G101', '2025-04-05', 1, 2, 1, 100, 50, 553.00), -- 商务座(1)
('G101', '2025-04-05', 1, 2, 2, 200, 120, 553.00), -- 一等座(2)
('G101', '2025-04-05', 1, 2, 3, 500, 300, 553.00), -- 二等座(3)
-- G201次2025-04-05余票
('G201', '2025-04-05', 3, 4, 1, 50, 30, 74.50), -- 商务座(1)
('G201', '2025-04-05', 3, 4, 2, 100, 80, 74.50), -- 一等座(2)
('G201', '2025-04-05', 3, 4, 3, 200, 150, 74.50), -- 二等座(3)
-- D301次2025-04-05余票
('D301', '2025-04-05', 5, 6, 3, 300, 200, 263.00), -- 二等座(3)
('D301', '2025-04-05', 5, 6, 4, 150, 100, 263.00), -- 硬卧(4)
('D301', '2025-04-05', 5, 6, 5, 400, 350, 263.00); -- 硬座(5)

-- 填充订单表（Orders）
INSERT INTO Orders (UserID, TotalAmount, STATUS, PaymentMethod, PaymentTime)
VALUES
(1, 1106.00, '已完成', '支付宝', '2025-04-01 10:00:00'),
(2, 149.00, '已完成', '微信支付', '2025-04-01 11:30:00'),
(3, 526.00, '已支付', '银联', '2025-04-02 09:15:00'),
(4, 74.50, '待支付', NULL, NULL),
(5, 263.00, '已取消', NULL, NULL);

-- 获取最新生成的OrderID（假设自增起始值为1）
SET @order1 = LAST_INSERT_ID();
SET @order2 = @order1 + 1;
SET @order3 = @order2 + 1;
SET @order4 = @order3 + 1;
SET @order5 = @order4 + 1;

-- 批量插入订单详情（性能优化）[1,4](@ref)
INSERT INTO OrderDetails (OrderID, TicketID, SeatTypeID, Quantity, UnitPrice)
VALUES
-- 订单1（用户1购买G101商务座2张）
(@order1, (SELECT TicketID FROM Tickets WHERE TrainID='G101' AND SeatTypeID=1), 1, 2, 553.00),

-- 订单2（用户2购买G201一等座2张）
(@order2, (SELECT TicketID FROM Tickets WHERE TrainID='G201' AND SeatTypeID=2), 2, 2, 74.50),

-- 订单3（用户3购买D301二等座和硬卧各1张）
(@order3, (SELECT TicketID FROM Tickets WHERE TrainID='D301' AND SeatTypeID=3), 3, 1, 263.00),
(@order3, (SELECT TicketID FROM Tickets WHERE TrainID='D301' AND SeatTypeID=4), 4, 1, 263.00),

-- 订单4（用户4购买G201二等座1张）
(@order4, (SELECT TicketID FROM Tickets WHERE TrainID='G201' AND SeatTypeID=3), 3, 1, 74.50),

-- 订单5（用户5购买D301硬座1张）
(@order5, (SELECT TicketID FROM Tickets WHERE TrainID='D301' AND SeatTypeID=5), 5, 1, 263.00);

COMMIT;