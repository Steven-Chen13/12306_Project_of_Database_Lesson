-- 1. 测试插入触发器
INSERT INTO Users (Username, PASSWORD, RealName, IDCard, Phone, Email, Gender)
VALUES ('trigger_test', 'e10adc3949ba59abbe56e057f20f883e', '触发器测试', '110101199007071240', '13800138007', 'trigger@example.com', 0);

SELECT * FROM UserRegistrationLogs WHERE Username = 'trigger_test';

-- 2. 测试更新触发器
SELECT TrainID, IsActive FROM Trains WHERE TrainID = 'G201';
UPDATE Trains SET IsActive = FALSE WHERE TrainID = 'G201';
SELECT * FROM TrainStatusAudit WHERE TrainID = 'G201';

-- 3. 测试删除触发器
INSERT INTO Orders (UserID, TotalAmount, STATUS) VALUES (2, 200.00, '待测试');
SET @test_order = LAST_INSERT_ID();
DELETE FROM Orders WHERE OrderID = @test_order;
SELECT * FROM DeletedOrdersBackup WHERE OrderID = @test_order;

-- 清理测试数据
DELETE FROM Users WHERE Username = 'trigger_test';
UPDATE Trains SET IsActive = TRUE WHERE TrainID = 'G201';