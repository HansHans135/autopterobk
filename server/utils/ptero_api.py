import aiohttp
import json
import os

app_path = os.path.dirname(os.path.dirname(__file__))

class PterodactylError(Exception):
    pass

class Ptero:
    def __init__(self, api_key, base_url):
        self.api_key = api_key
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        self.base_url = base_url if base_url.endswith("/") else base_url + "/"
        print(self.__dict__)

    async def get_servers(self, use_cache=True) -> list:
        if not os.path.isfile(f"{app_path}/data/server_tmp.cache"):
            use_cache = False
        if use_cache:
            with open(f"{app_path}/data/server_tmp.cache", "r", encoding="utf-8") as f:
                server_list = json.load(f)
                return server_list
        else:
            headers = self.headers
            url = f'{self.base_url}api/application/servers'
            server_list = []
            while True:
                async with aiohttp.ClientSession(headers=headers) as session:
                    async with session.get(url) as response:
                        data = await response.json()
                        if data.get("errors"):
                            raise PterodactylError(data['errors'][0])
                        server_list += data["data"]
                        try:
                            url = data["meta"]["pagination"]["links"]["next"]
                        except:
                            with open(f"{app_path}/data/server_tmp.cache", "w", encoding="utf-8") as f:
                                json.dump(server_list, f,
                                          ensure_ascii=False, indent=4)
                            return server_list
