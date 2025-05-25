-- 创建余票表（针对索引实验优化版）
CREATE TABLE Tickets (
  TicketID BIGINT NOT NULL AUTO_INCREMENT,
  TrainID VARCHAR(10) NOT NULL,
  DepartureDate DATE NOT NULL,
  FromStationID INT NOT NULL,
  ToStationID INT NOT NULL,
  SeatTypeID INT NOT NULL,
  TotalCount INT NOT NULL,
  AvailableCount INT NOT NULL,
  Price DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (TicketID),
  -- 基本索引（保留业务需要的索引）
  INDEX idx_train_date (TrainID, DepartureDate),
  INDEX idx_route (TrainID, FromStationID, ToStationID),
  -- 添加用于实验的索引
  INDEX idx_seat_type (SeatTypeID),  -- 用于测试的单个字段索引
  INDEX idx_from_station (FromStationID),  -- 另一个可能测试的索引
  -- 业务约束
  CONSTRAINT chk_count_valid CHECK (AvailableCount BETWEEN 0 AND TotalCount),
  CONSTRAINT chk_price_positive CHECK (Price > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;