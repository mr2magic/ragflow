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


class BraveSearchParam(ToolParamBase):
    """
    Define the Brave Search component parameters.
    """

    def __init__(self):
        self.meta: ToolMeta = {
            "name": "brave_search",
            "description": """
Brave Search is a privacy-focused search engine that provides independent web search results.
When searching:
   - Start with a specific query focused on a single aspect.
   - Keep queries concise (fewer than 5 keywords).
   - Broaden search terms if needed.
   - Cross-reference information from multiple sources.
            """,
            "parameters": {
                "query": {
                    "type": "string",
                    "description": "The search keywords to execute with Brave Search. Should be the most important words/terms from the original request.",
                    "default": "{sys.query}",
                    "required": True,
                },
                "count": {
                    "type": "integer",
                    "description": "Number of search results to return (1-20, default 6).",
                    "default": 6,
                    "required": False,
                },
                "search_lang": {
                    "type": "string",
                    "description": "Language code for search results, e.g. 'en', 'fr', 'de'. Default is 'en'.",
                    "default": "en",
                    "required": False,
                },
                "freshness": {
                    "type": "string",
                    "description": "Filter results by recency: 'pd' (past day), 'pw' (past week), 'pm' (past month), 'py' (past year). Leave empty for no filter.",
                    "enum": ["pd", "pw", "pm", "py", ""],
                    "default": "",
                    "required": False,
                },
            },
        }
        super().__init__()
        self.api_key = os.environ.get("BRAVE_SEARCH_API_KEY", "")
        self.count = 6
        self.search_lang = "en"
        self.freshness = ""

    def check(self):
        self.check_empty(self.api_key, "Brave Search API key")
        self.check_positive_integer(self.count, "Brave Search count should be between 1 and 20")

    def get_input_form(self) -> dict[str, dict]:
        return {
            "query": {
                "name": "Query",
                "type": "line",
            }
        }


class BraveSearch(ToolBase, ABC):
    component_name = "BraveSearch"

    _API_URL = "https://api.search.brave.com/res/v1/web/search"

    @timeout(int(os.environ.get("COMPONENT_EXEC_TIMEOUT", 12)))
    def _invoke(self, **kwargs):
        if self.check_if_canceled("BraveSearch processing"):
            return

        if not kwargs.get("query"):
            self.set_output("formalized_content", "")
            return ""

        headers = {
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "X-Subscription-Token": self._param.api_key,
        }
        params = {
            "q": kwargs["query"],
            "count": kwargs.get("count", self._param.count),
            "search_lang": kwargs.get("search_lang", self._param.search_lang),
        }
        freshness = kwargs.get("freshness", self._param.freshness)
        if freshness:
            params["freshness"] = freshness

        last_e = None
        for _ in range(self._param.max_retries + 1):
            if self.check_if_canceled("BraveSearch processing"):
                return

            try:
                resp = requests.get(self._API_URL, headers=headers, params=params, timeout=10)
                resp.raise_for_status()
                data = resp.json()

                if self.check_if_canceled("BraveSearch processing"):
                    return

                results = data.get("web", {}).get("results", [])
                self._retrieve_chunks(
                    results,
                    get_title=lambda r: r.get("title", ""),
                    get_url=lambda r: r.get("url", ""),
                    get_content=lambda r: r.get("extra_snippets", [r.get("description", "")])[0]
                    if r.get("extra_snippets")
                    else r.get("description", ""),
                    get_score=lambda r: r.get("score", 1),
                )
                self.set_output("json", results)
                return self.output("formalized_content")
            except Exception as e:
                if self.check_if_canceled("BraveSearch processing"):
                    return

                last_e = e
                logging.exception(f"Brave Search error: {e}")
                time.sleep(self._param.delay_after_error)

        if last_e:
            self.set_output("_ERROR", str(last_e))
            return f"Brave Search error: {last_e}"

        assert False, self.output()

    def thoughts(self) -> str:
        return """
Keywords: {}
Looking for the most relevant articles.
        """.format(self.get_input().get("query", "-_-!"))
