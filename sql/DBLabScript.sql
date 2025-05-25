-- 创建座位类型表（需先创建）
CREATE TABLE SeatTypes (
    SeatTypeID INT NOT NULL AUTO_INCREMENT,
    TypeName VARCHAR(20) NOT NULL,
    Description VARCHAR(100),
    PRIMARY KEY (SeatTypeID),
    UNIQUE KEY (TypeName)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 创建用户表
CREATE TABLE Users (
  UserID INT NOT NULL AUTO_INCREMENT,
  Username VARCHAR (50) NOT NULL,
  PASSWORD VARCHAR (100) NOT NULL,
  RealName VARCHAR (50) NOT NULL,
  IDCard VARCHAR (18) NOT NULL,
  Phone VARCHAR (20),
  Email VARCHAR (100),
  Gender TINYINT NOT NULL,
  RegisterTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (UserID),
  -- UNIQUE KEY (Username),
  UNIQUE KEY (IDCard)
  -- CONSTRAINT chk_gender CHECK (Gender IN (0,1)),
  -- CONSTRAINT chk_idcard_length CHECK (LENGTH(IDCard) = 18)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- 创建车次表
CREATE TABLE Trains (
  TrainID VARCHAR (10) NOT NULL,
  TrainType VARCHAR (20) NOT NULL,
  StartStation VARCHAR (50) NOT NULL,
  EndStation VARCHAR (50) NOT NULL,
  DepartureTime TIME NOT NULL,
  ArrivalTime TIME NOT NULL,
  Duration INT NOT NULL COMMENT '分钟数',
  IsActive BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (TrainID),
  INDEX (StartStation),
  INDEX (EndStation),
  CONSTRAINT chk_duration CHECK (Duration > 0),
  CONSTRAINT chk_time_sequence CHECK (DepartureTime < ArrivalTime)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- 创建车站表
CREATE TABLE Stations (
  StationID INT NOT NULL AUTO_INCREMENT,
  StationName VARCHAR (50) NOT NULL,
  StationCode VARCHAR (10) NOT NULL,
  City VARCHAR (50) NOT NULL,
  Province VARCHAR (50) NOT NULL,
  PRIMARY KEY (StationID),
  UNIQUE KEY (StationName),
  UNIQUE KEY (StationCode)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- 创建车次-车站关联表
CREATE TABLE TrainStops (
  ID INT NOT NULL AUTO_INCREMENT,
  TrainID VARCHAR (10) NOT NULL,
  StationID INT NOT NULL,
  ArrivalTime TIME,
  DepartureTime TIME,
  StopOrder INT NOT NULL,
  Distance INT COMMENT '距离始发站公里数',
  PRIMARY KEY (ID),
  FOREIGN KEY (TrainID) REFERENCES Trains(TrainID) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (StationID) REFERENCES Stations(StationID) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE KEY (TrainID, StationID),
  INDEX (TrainID, StopOrder)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- 创建余票表
CREATE TABLE Tickets (
  TicketID BIGINT NOT NULL AUTO_INCREMENT,
  TrainID VARCHAR (10) NOT NULL,
  DepartureDate DATE NOT NULL,
  FromStationID INT NOT NULL,
  ToStationID INT NOT NULL,
  SeatTypeID INT NOT NULL,
  TotalCount INT NOT NULL,
  AvailableCount INT NOT NULL,
  Price DECIMAL (10, 2) NOT NULL,
  PRIMARY KEY (TicketID),
  FOREIGN KEY (TrainID) REFERENCES Trains(TrainID) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (FromStationID) REFERENCES Stations(StationID) ON DELETE RESTRICT ON UPDATE CASCADE,
  FOREIGN KEY (ToStationID) REFERENCES Stations(StationID) ON DELETE RESTRICT ON UPDATE CASCADE,
  FOREIGN KEY (SeatTypeID) REFERENCES SeatTypes(SeatTypeID) ON DELETE RESTRICT ON UPDATE CASCADE,
  INDEX (TrainID, DepartureDate),
  INDEX (TrainID, FromStationID, ToStationID),
  CONSTRAINT chk_count_valid CHECK (AvailableCount BETWEEN 0 AND TotalCount),
  CONSTRAINT chk_price_positive CHECK (Price > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- 创建订单表
CREATE TABLE Orders (
  OrderID BIGINT NOT NULL AUTO_INCREMENT,
  UserID INT NOT NULL,
  OrderTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  TotalAmount DECIMAL (10, 2) NOT NULL,
  STATUS VARCHAR (20) NOT NULL,
  PaymentMethod VARCHAR (20),
  PaymentTime DATETIME,
  PRIMARY KEY (OrderID),
  FOREIGN KEY (UserID) REFERENCES Users (UserID),
  INDEX (UserID, STATUS)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- 创建订单详情表（记录每笔订单的具体票务信息）
CREATE TABLE OrderDetails (
    OrderDetailID BIGINT NOT NULL AUTO_INCREMENT,
    OrderID BIGINT NOT NULL,
    TicketID BIGINT NOT NULL,  -- 关联余票表 Tickets
    SeatTypeID INT NOT NULL,   -- 关联座位类型 SeatTypes
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (OrderDetailID),
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID) ON DELETE CASCADE,
    FOREIGN KEY (TicketID) REFERENCES Tickets(TicketID) ON DELETE RESTRICT,
    FOREIGN KEY (SeatTypeID) REFERENCES SeatTypes(SeatTypeID) ON DELETE RESTRICT,
    INDEX (OrderID, SeatTypeID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 在用户表上创建聚集索引(主键已经是聚集索引)
ALTER TABLE Users ADD INDEX idx_gender (Gender);

-- 在余票表上创建唯一索引
CREATE UNIQUE INDEX idx_ticket_unique ON Tickets (TrainID, DepartureDate, FromStationID, ToStationID, SeatTypeID);

-- 行列子集视图：显示用户基本信息（隐藏敏感信息）
CREATE VIEW user_basic_info AS
SELECT UserID, Username, Phone, Email, Gender, RegisterTime
FROM Users;

-- 带表达式的视图：计算车票价格折扣
CREATE VIEW ticket_price_with_discount AS
SELECT 
    t.TrainID,
    t.StartStation,
    t.EndStation,
    tk.Price AS original_price,
    ROUND(tk.Price * 0.9, 2) AS discounted_price,
    tk.AvailableCount
FROM Trains t
JOIN Tickets tk ON t.TrainID = tk.TrainID;

-- 分组视图：按车次统计余票情况
CREATE VIEW train_ticket_stats AS
SELECT 
    t.TrainID,
    t.StartStation,
    t.EndStation,
    st.TypeName AS SeatType,
    SUM(tk.AvailableCount) AS TotalAvailable,
    MIN(tk.Price) AS MinPrice,
    MAX(tk.Price) AS MaxPrice
FROM Trains t
JOIN Tickets tk ON t.TrainID = tk.TrainID
JOIN SeatTypes st ON tk.SeatTypeID = st.SeatTypeID
GROUP BY t.TrainID, t.StartStation, t.EndStation, st.TypeName;