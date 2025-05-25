from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error, pooling
from datetime import datetime, timedelta
import logging

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 数据库连接池配置
db_config = {
    'host': 'localhost',
    'user': 'root',
    'password': 'YOUR_PASSWORD',
    'database': '12306_railway',
    'pool_name': 'mypool',
    'pool_size': 5,
    'pool_reset_session': True
}

# 创建连接池
try:
    connection_pool = pooling.MySQLConnectionPool(**db_config)
    logger.info("成功创建数据库连接池")
except Error as e:
    logger.error(f"创建数据库连接池失败: {e}")
    connection_pool = None

def get_db_connection():
    if not connection_pool:
        return None
    try:
        return connection_pool.get_connection()
    except Error as e:
        logger.error(f"从连接池获取连接失败: {e}")
        return None

# 健康检查端点
@app.route('/api/health', methods=['GET'])
def health_check():
    if not connection_pool:
        return jsonify({'status': 'error', 'message': 'Database pool not initialized'}), 500
    
    try:
        conn = get_db_connection()
        if not conn:
            return jsonify({'status': 'error', 'message': 'Failed to get database connection'}), 500
            
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        
        return jsonify({
            'status': 'success',
            'message': 'API and database are healthy',
            'timestamp': datetime.now().isoformat()
        })
    except Error as e:
        logger.error(f"健康检查失败: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

# 车站列表
@app.route('/api/stations', methods=['GET'])
def get_stations():
    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': '数据库连接失败'}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT StationID as id, StationName as name FROM Stations ORDER BY StationName")
        stations = cursor.fetchall()
        return jsonify({'success': True, 'data': stations})
    except Error as e:
        logger.error(f"获取车站列表错误: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

# 座位类型
@app.route('/api/seat_types', methods=['GET'])
def get_seat_types():
    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': '数据库连接失败'}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT SeatTypeID as id, TypeName as name FROM SeatTypes ORDER BY SeatTypeID")
        seat_types = cursor.fetchall()
        return jsonify({'success': True, 'data': seat_types})
    except Error as e:
        logger.error(f"获取座位类型错误: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

# 查询余票（使用存储过程）
@app.route('/api/query_tickets', methods=['POST'])
def query_tickets():
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': '缺少请求数据'}), 400
        
    depart_date = data.get('depart_date')
    from_station = data.get('from_station')
    to_station = data.get('to_station')

    if not all([depart_date, from_station, to_station]):
        return jsonify({'success': False, 'error': '缺少必要参数'}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': '数据库连接失败'}), 500

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
                if 'Price' in row:
                    row['Price'] = float(row['Price'])
                if 'AvailableCount' in row:
                    row['AvailableCount'] = int(row['AvailableCount'])
                
                # 处理DepartureDate
                if 'DepartureDate' in row and hasattr(row['DepartureDate'], 'strftime'):
                    row['DepartureDate'] = row['DepartureDate'].strftime('%Y-%m-%d')
                
                # 处理timedelta类型的时间
                if 'DepartureTime' in row and isinstance(row['DepartureTime'], timedelta):  # 使用直接导入的timedelta
                    # 将timedelta转换为HH:MM格式字符串
                    total_seconds = int(row['DepartureTime'].total_seconds())
                    hours = total_seconds // 3600
                    minutes = (total_seconds % 3600) // 60
                    row['DepartureTime'] = f"{hours:02d}:{minutes:02d}"
                
                if 'ArrivalTime' in row and isinstance(row['ArrivalTime'], timedelta):  # 使用直接导入的timedelta
                    # 将timedelta转换为HH:MM格式字符串
                    total_seconds = int(row['ArrivalTime'].total_seconds())
                    hours = total_seconds // 3600
                    minutes = (total_seconds % 3600) // 60
                    row['ArrivalTime'] = f"{hours:02d}:{minutes:02d}"
                
                tickets.append(row)
        
        logger.info(f"处理后车票数据示例: {tickets[:1]}")
        
        if not tickets:
            return jsonify({'success': True, 'data': [], 'message': '未查询到符合条件的车票'})
        
        return jsonify({'success': True, 'data': tickets})
    
    except Error as e:
        logger.error(f"查询余票错误: {e}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500
    except Exception as e:
        logger.error(f"处理余票查询时发生意外错误: {e}", exc_info=True)
        return jsonify({'success': False, 'error': '内部服务器错误'}), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

# 创建订单（使用存储过程）- 修改版
@app.route('/api/create_order', methods=['POST'])
def create_order():
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': '缺少请求数据'}), 400
        
    required_fields = ['user_id', 'train_id', 'depart_date', 'seat_type_id', 'ticket_count']
    if not all(field in data for field in required_fields):
        return jsonify({'success': False, 'error': '缺少必要字段'}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': '数据库连接失败'}), 500

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
            try:
                order_id = int(order_result['order_id'])
                total_amount = float(order_result.get('total_amount', 0.0))
                status = str(order_result.get('status', '待支付'))
                
                conn.commit()
                
                logger.info(f"订单创建成功: order_id={order_id}, total_amount={total_amount}, status={status}")
                
                return jsonify({
                    'success': True,
                    'message': '订单创建成功',
                    'order_id': order_id,
                    'total_amount': total_amount,
                    'status': status
                })
            except (ValueError, TypeError) as e:
                logger.error(f"数据类型转换错误: {e}", exc_info=True)
                conn.rollback()
                return jsonify({
                    'success': False,
                    'error': '订单创建成功，但返回数据格式有误',
                    'order_id': str(order_result.get('order_id', '')),
                    'debug_info': str(order_result)
                }), 500
        
        # 如果没有返回order_id，但数据库已更新
        conn.commit()  # 确保提交事务
        logger.warning("存储过程未返回order_id，但数据库可能已更新")
        
        # 尝试从数据库查询最新订单
        cursor.execute("""
            SELECT OrderID as order_id, TotalAmount as total_amount, Status 
            FROM Orders 
            WHERE UserID = %s 
            ORDER BY OrderTime DESC 
            LIMIT 1
        """, (data['user_id'],))
        latest_order = cursor.fetchone()
        
        if latest_order:
            logger.info(f"从数据库查询到最新订单: {latest_order}")
            return jsonify({
                'success': True,
                'message': '订单创建成功(从数据库确认)',
                'order_id': latest_order['order_id'],
                'total_amount': float(latest_order['total_amount']),
                'status': latest_order['Status']
            })
        
        return jsonify({
            'success': False,
            'error': '订单可能已创建，但无法确认',
            'debug_info': str(order_result) if order_result else '无返回结果'
        }), 500
        
    except Error as e:
        conn.rollback()
        logger.error(f"创建订单数据库错误: {e}", exc_info=True)
        return jsonify({
            'success': False,
            'error': '数据库错误: ' + str(e),
            'debug_info': '检查数据库日志获取更多信息'
        }), 500
    except Exception as e:
        conn.rollback()
        logger.error(f"创建订单未知错误: {e}", exc_info=True)
        return jsonify({
            'success': False,
            'error': '未知错误',
            'debug_info': str(e)
        }), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

# 查询订单
@app.route('/api/orders', methods=['GET'])
def get_orders():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'success': False, 'error': '缺少user_id参数'}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': '数据库连接失败'}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        
        # 查询主订单信息
        cursor.execute("""
            SELECT 
                o.OrderID as order_id,
                o.OrderTime as order_time,
                CAST(o.TotalAmount AS FLOAT) as total_amount,  # 关键修改
                o.Status as status
            FROM Orders o
            WHERE o.UserID = %s
            ORDER BY o.OrderTime DESC
        """, (user_id,))
        
        orders = []
        for order in cursor.fetchall():
            # order['total_amount'] = order(order['total_amount']) if order['total_amount'] is not None else 0.0
            # 查询每个订单的详情
            cursor.execute("""
                SELECT 
                    od.OrderDetailID,
                    od.TicketID,
                    od.SeatTypeID,
                    st.TypeName as seat_type,
                    od.Quantity,
                    od.UnitPrice,
                    t.TrainID,
                    tk.DepartureDate,
                    s_from.StationName as from_station,
                    s_to.StationName as to_station
                FROM OrderDetails od
                JOIN Tickets tk ON od.TicketID = tk.TicketID
                JOIN Trains t ON tk.TrainID = t.TrainID
                JOIN SeatTypes st ON od.SeatTypeID = st.SeatTypeID
                JOIN Stations s_from ON tk.FromStationID = s_from.StationID
                JOIN Stations s_to ON tk.ToStationID = s_to.StationID
                WHERE od.OrderID = %s
            """, (order['order_id'],))
            
            details = cursor.fetchall()
            logger.info(f"查询到订单 {order['order_id']} 的详情: {details}")
            for detail in details:
                detail['depart_date'] = detail['DepartureDate'].strftime('%Y-%m-%d')
                detail['unit_price'] = float(detail['UnitPrice'])
            
            order['order_time'] = order['order_time'].strftime('%Y-%m-%d %H:%M:%S')
            order['details'] = details
            logger.info(f"处理后的订单数据: {order}")
            orders.append(order)
        
        return jsonify({'success': True, 'data': orders})
    except Error as e:
        logger.error(f"查询订单错误: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()

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

@app.route('/api/change_ticket', methods=['POST'])
def change_ticket():
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'error': '缺少请求数据'}), 400
    
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
    if not data['new_train_id']:
        return jsonify({'success': False, 'error': '请选择新车次'}), 400
    
    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': '数据库连接失败'}), 500
        
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

            
    except Error as e:
        conn.rollback()
        logger.error(f"改签错误: {e}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500
    except ValueError as e:
        conn.rollback()
        logger.error(f"票数格式错误: {e}", exc_info=True)
        return jsonify({'success': False, 'error': '票数必须是整数'}), 400
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()


    

# 全局错误处理
@app.errorhandler(404)
def not_found(error):
    return jsonify({'success': False, 'error': '资源未找到'}), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"服务器错误: {str(error)}")
    return jsonify({
        'success': False,
        'error': '内部服务器错误',
        'message': str(error)
    }), 500

if __name__ == '__main__':
    app.run(debug=True, port=5000, host='0.0.0.0')
