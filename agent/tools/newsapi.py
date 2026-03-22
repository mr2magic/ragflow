#
#  Copyright 2024 The InfiniFlow Authors. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
import logging
import os
import time
from abc import ABC

import requests

from agent.tools.base import ToolParamBase, ToolBase, ToolMeta
from common.connection_utils import timeout


class NewsAPIParam(ToolParamBase):
    """
    Define the NewsAPI component parameters.
    """

    def __init__(self):
        self.meta: ToolMeta = {
            "name": "news_search",
            "description": """
Search real-time news articles from thousands of sources worldwide using NewsAPI.
Use it for:
   - Breaking news and current events
   - News about specific companies, people, or topics
   - Trending stories in specific categories
            """,
            "parameters": {
                "query": {
                    "type": "string",
                    "description": "Keywords or phrases to search for in news articles.",
                    "default": "{sys.query}",
                    "required": True,
                },
                "language": {
                    "type": "string",
                    "description": "2-letter ISO language code for results. Default: en.",
                    "default": "en",
                    "required": False,
                },
                "sort_by": {
                    "type": "string",
                    "description": "Sort order: relevancy, popularity, or publishedAt (newest first).",
                    "enum": ["relevancy", "popularity", "publishedAt"],
                    "default": "relevancy",
                    "required": False,
                },
            },
        }
        super().__init__()
        self.api_key = os.environ.get("NEWSAPI_API_KEY", "")
        self.language = "en"
        self.sort_by = "relevancy"
        self.max_results = 6

    def check(self):
        self.check_empty(self.api_key, "NewsAPI API key")

    def get_input_form(self) -> dict[str, dict]:
        return {
            "query": {
                "name": "Query",
                "type": "line",
            }
        }


class NewsAPI(ToolBase, ABC):
    component_name = "NewsAPI"

    _API_URL = "https://newsapi.org/v2/everything"

    @timeout(int(os.environ.get("COMPONENT_EXEC_TIMEOUT", 12)))
    def _invoke(self, **kwargs):
        if self.check_if_canceled("NewsAPI processing"):
            return

        query = kwargs.get("query", "")
        if not query:
            self.set_output("formalized_content", "")
            return ""

        params = {
            "q": query,
            "language": kwargs.get("language", self._param.language),
            "sortBy": kwargs.get("sort_by", self._param.sort_by),
            "pageSize": self._param.max_results,
            "apiKey": self._param.api_key,
        }

        last_e = None
        for _ in range(self._param.max_retries + 1):
            if self.check_if_canceled("NewsAPI processing"):
                return

            try:
                resp = requests.get(self._API_URL, params=params, timeout=10)
                resp.raise_for_status()
                data = resp.json()

                if self.check_if_canceled("NewsAPI processing"):
                    return

                articles = data.get("articles", [])
                self._retrieve_chunks(
                    articles,
                    get_title=lambda r: r.get("title", ""),
                    get_url=lambda r: r.get("url", ""),
                    get_content=lambda r: (r.get("content") or r.get("description") or ""),
                )
                self.set_output("json", articles)
                return self.output("formalized_content")
            except Exception as e:
                if self.check_if_canceled("NewsAPI processing"):
                    return

                last_e = e
                logging.exception(f"NewsAPI error: {e}")
                time.sleep(self._param.delay_after_error)

        if last_e:
            self.set_output("_ERROR", str(last_e))
            return f"NewsAPI error: {last_e}"

        assert False, self.output()

    def thoughts(self) -> str:
        return "Keywords: {}\nSearching latest news...".format(
            self.get_input().get("query", "-_-!")
        )
