from flask import Flask, jsonify, render_template, request, redirect, url_for, flash, session
from werkzeug.utils import secure_filename
from types import SimpleNamespace
import json
import os
from datetime import datetime
from utils.ptero_api import Ptero
import uuid
import asyncio
from functools import wraps

app_path = os.path.dirname(__file__)
print(f"{app_path}/config.json")
with open(f"{app_path}/config.json") as f:
    config = SimpleNamespace(**json.load(f))
    if hasattr(config, 'account') and isinstance(config.account, dict):
        config.account = SimpleNamespace(**config.account)

app = Flask(__name__)
app.secret_key = getattr(config, 'secret_key', config.key)
app.config["MAX_CONTENT_LENGTH"] = config.max_size * 1024 * 1024 * 1024
app.permanent_session_lifetime = 1800 

ptero = Ptero(config.api_key, config.base_url)
asyncio.run(ptero.get_servers(use_cache=False))

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login', next=request.url))
        return f(*args, **kwargs)
    return decorated_function

def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in {
        "gz",
        "tar",
    }


def load_servers():
    """載入伺服器配置"""
    try:
        with open(f"{app_path}/server.json") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_servers(servers_data):
    """儲存伺服器配置"""
    with open(f"{app_path}/server.json", 'w', encoding='utf-8') as f:
        json.dump(servers_data, f, ensure_ascii=False, indent=4)

def load_server_tmp():
    """載入 server_tmp.cache 文件內容"""
    try:
        with open(f"{app_path}/data/server_tmp.cache") as f:
            data = json.load(f)
            # 提取伺服器資料
            servers_info = []
            for item in data:
                if item.get('object') == 'server' and 'attributes' in item:
                    attrs = item['attributes']
                    servers_info.append({
                        'uuid': attrs.get('uuid'),
                        'id': attrs.get('id'),
                        'identifier': attrs.get('identifier'),
                        'name': attrs.get('name'),
                        'memory': attrs.get('limits', {}).get('memory', 0),
                        'disk': attrs.get('limits', {}).get('disk', 0),
                        'cpu': attrs.get('limits', {}).get('cpu', 0),
                        'node': attrs.get('node')
                    })
            return servers_info
    except (FileNotFoundError, json.JSONDecodeError):
        return []


@app.route("/")
def index():
    if 'logged_in' in session:
        return redirect(url_for('admin_panel'))
    return redirect(url_for('login'))

@app.route("/login", methods=['GET', 'POST'])
def login():
    if 'logged_in' in session:
        return redirect(url_for('admin_panel'))
        
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if (hasattr(config, 'account') and 
            username == config.account.username and 
            password == config.account.password):
            session.permanent = True
            session['logged_in'] = True
            session['username'] = username
            flash('登入成功', 'success')
            
            next_page = request.args.get('next')
            return redirect(next_page or url_for('admin_panel'))
        else:
            flash('用戶名或密碼錯誤', 'error')
            
    return render_template('login.html')

@app.route("/logout")
def logout():
    session.clear()
    flash('您已成功登出', 'info')
    return redirect(url_for('login'))

@app.route("/uploader", methods=["POST"])
def upload():
    key = request.form.get("api_key")
    if "file" not in request.files:
        return "No file part"
    file = request.files["file"]
    if file.filename == "":
        return "No selected file"
    if file and allowed_file(file.filename) and config.key == key:
        filename = secure_filename(file.filename)
        if not os.path.exists(f"{app_path}/data"):
            os.makedirs(f"{app_path}/data")

        file.save(os.path.join(f"{app_path}/data", filename))
        return jsonify({"status": 200}), 200
    else:
        return jsonify({"status": 403}), 403


@app.route("/api/path")
def api_path():
    return config.data_path


def get_server_details(server_uuid):
    server_tmp_data = load_server_tmp()
    for server in server_tmp_data:
        if server.get('uuid') == server_uuid:
            return server
    
    return {
        'uuid': server_uuid,
        'name': f'Unknown Server ({server_uuid[:8]}...)',
        'id': 'N/A',
        'identifier': server_uuid[:8],
        'memory': 'N/A',
        'disk': 'N/A',
        'cpu': 'N/A',
        'node': 'N/A'
    }

@app.route("/admin")
@login_required
def admin_panel():
    servers = load_servers()
    all_tmp_data = load_server_tmp()
    
    server_tmp_data = [s for s in all_tmp_data if s.get('uuid') not in servers]
    
    managed_servers = {}
    for server_uuid, excludes in servers.items():
        server_details = get_server_details(server_uuid)
        managed_servers[server_uuid] = {
            'details': server_details,
            'excludes': excludes
        }
    
    return render_template('admin.html', 
                         servers=servers,
                         managed_servers=managed_servers,
                         server_tmp_data=server_tmp_data,
                         config=config)

@app.route("/admin/add_server", methods=['POST'])
@login_required
def add_server():
    server_tmp_data = load_server_tmp()
    
    if not server_tmp_data:
        flash('server_tmp.cache 文件為空或不存在', 'error')
        return redirect(url_for('admin_panel'))
    
    servers = load_servers()
    added_count = 0
    
    selected_servers = request.form.getlist('selected_servers')
    
    if selected_servers:
        for server_info in server_tmp_data:
            server_uuid = server_info.get('uuid')
            if server_uuid in selected_servers and server_uuid not in servers:
                servers[server_uuid] = []
                added_count += 1
    else:
        for server_info in server_tmp_data:
            server_uuid = server_info.get('uuid')
            if server_uuid and server_uuid not in servers:
                servers[server_uuid] = []
                added_count += 1
    
    if added_count > 0:
        save_servers(servers)
        flash(f'成功添加 {added_count} 個伺服器', 'success')
    else:
        flash('沒有新的伺服器需要添加或選擇的伺服器已存在', 'info')
    
    return redirect(url_for('admin_panel'))

@app.route("/admin/remove_server/<server_uuid>", methods=['POST'])
@login_required
def remove_server(server_uuid):
    servers = load_servers()
    
    if server_uuid in servers:
        del servers[server_uuid]
        save_servers(servers)
        flash(f'成功移除伺服器 {server_uuid[:8]}...', 'success')
    else:
        flash('伺服器不存在', 'error')
    
    return redirect(url_for('admin_panel'))

@app.route("/admin/update_excludes/<server_uuid>", methods=['POST'])
@login_required
def update_excludes(server_uuid):
    servers = load_servers()
    
    if server_uuid not in servers:
        flash('伺服器不存在', 'error')
        return redirect(url_for('admin_panel'))
    
    excludes = request.form.get('excludes', '')
    excludes_list = [x.strip() for x in excludes.split('\n') if x.strip()]
    
    servers[server_uuid] = excludes_list
    save_servers(servers)
    
    flash(f'成功更新伺服器 {server_uuid[:8]}... 的排除檔案列表', 'success')
    return redirect(url_for('admin_panel'))

@app.route("/admin/config")
@login_required
def view_config():
    try:
        with open(f"{app_path}/config.json") as f:
            config_data = json.load(f)
        return render_template('config.html', config_data=config_data)
    except Exception as e:
        flash(f'無法讀取配置文件: {str(e)}', 'error')
        return redirect(url_for('admin_panel'))

@app.route("/api/list")
def api_list():
    with open(f"{app_path}/server.json") as f:
        data = json.load(f)
    for i in data:
        data[i] += config.system_exclude
    return data


app.run(host=config.host, port=config.port, debug=True)
