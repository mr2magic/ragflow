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


class OpenMeteoParam(ToolParamBase):
    """
    Define the Open-Meteo weather component parameters.
    No API key required.
    """

    def __init__(self):
        self.meta: ToolMeta = {
            "name": "weather_forecast",
            "description": """
Get free weather forecasts and current conditions using Open-Meteo (no API key required).
Use it for:
   - Current temperature and conditions at a location
   - Multi-day weather forecasts
   - Historical weather data
Provide latitude and longitude for the location.
            """,
            "parameters": {
                "latitude": {
                    "type": "number",
                    "description": "Latitude of the location (e.g. 32.78 for Charleston, SC).",
                    "default": 32.78,
                    "required": True,
                },
                "longitude": {
                    "type": "number",
                    "description": "Longitude of the location (e.g. -79.93 for Charleston, SC).",
                    "default": -79.93,
                    "required": True,
                },
                "forecast_days": {
                    "type": "integer",
                    "description": "Number of forecast days (1-16). Default: 7.",
                    "default": 7,
                    "required": False,
                },
            },
        }
        super().__init__()
        self.forecast_days = 7

    def check(self):
        self.check_positive_integer(self.forecast_days, "Forecast days must be between 1 and 16")

    def get_input_form(self) -> dict[str, dict]:
        return {
            "latitude": {"name": "Latitude", "type": "line"},
            "longitude": {"name": "Longitude", "type": "line"},
        }


class OpenMeteo(ToolBase, ABC):
    component_name = "OpenMeteo"

    _API_URL = "https://api.open-meteo.com/v1/forecast"
    _WMO_CODES = {
        0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
        45: "Fog", 48: "Icy fog", 51: "Light drizzle", 53: "Moderate drizzle",
        55: "Dense drizzle", 61: "Slight rain", 63: "Moderate rain", 65: "Heavy rain",
        71: "Slight snow", 73: "Moderate snow", 75: "Heavy snow", 77: "Snow grains",
        80: "Slight showers", 81: "Moderate showers", 82: "Violent showers",
        85: "Slight snow showers", 86: "Heavy snow showers",
        95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with heavy hail",
    }

    @timeout(int(os.environ.get("COMPONENT_EXEC_TIMEOUT", 12)))
    def _invoke(self, **kwargs):
        if self.check_if_canceled("OpenMeteo processing"):
            return

        lat = kwargs.get("latitude", self._param.latitude)
        lon = kwargs.get("longitude", self._param.longitude)
        forecast_days = kwargs.get("forecast_days", self._param.forecast_days)

        params = {
            "latitude": lat,
            "longitude": lon,
            "current": ["temperature_2m", "relative_humidity_2m", "wind_speed_10m", "weather_code"],
            "daily": ["temperature_2m_max", "temperature_2m_min", "weather_code", "precipitation_sum"],
            "forecast_days": forecast_days,
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "precipitation_unit": "inch",
        }

        last_e = None
        for _ in range(self._param.max_retries + 1):
            if self.check_if_canceled("OpenMeteo processing"):
                return

            try:
                resp = requests.get(self._API_URL, params=params, timeout=10)
                resp.raise_for_status()
                data = resp.json()

                if self.check_if_canceled("OpenMeteo processing"):
                    return

                current = data.get("current", {})
                daily = data.get("daily", {})
                dates = daily.get("time", [])

                current_desc = self._WMO_CODES.get(current.get("weather_code", 0), "Unknown")
                lines = [
                    f"**Current conditions** at ({lat}, {lon}):",
                    f"- Temperature: {current.get('temperature_2m')}°F",
                    f"- Humidity: {current.get('relative_humidity_2m')}%",
                    f"- Wind: {current.get('wind_speed_10m')} mph",
                    f"- Conditions: {current_desc}",
                    "",
                    f"**{forecast_days}-day forecast:**",
                ]
                for i, date in enumerate(dates):
                    wmo = (daily.get("weather_code") or [])[i] if daily.get("weather_code") else 0
                    desc = self._WMO_CODES.get(wmo, "Unknown")
                    hi = (daily.get("temperature_2m_max") or [])[i] if daily.get("temperature_2m_max") else "N/A"
                    lo = (daily.get("temperature_2m_min") or [])[i] if daily.get("temperature_2m_min") else "N/A"
                    rain = (daily.get("precipitation_sum") or [])[i] if daily.get("precipitation_sum") else 0
                    lines.append(f"- {date}: {desc}, High {hi}°F / Low {lo}°F, Precip {rain}\"")

                summary = "\n".join(lines)
                results = [{"title": f"Weather at ({lat}, {lon})", "url": "https://open-meteo.com", "content": summary}]

                self._retrieve_chunks(
                    results,
                    get_title=lambda r: r["title"],
                    get_url=lambda r: r["url"],
                    get_content=lambda r: r["content"],
                )
                self.set_output("json", data)
                return self.output("formalized_content")
            except Exception as e:
                if self.check_if_canceled("OpenMeteo processing"):
                    return

                last_e = e
                logging.exception(f"OpenMeteo error: {e}")
                time.sleep(self._param.delay_after_error)

        if last_e:
            self.set_output("_ERROR", str(last_e))
            return f"OpenMeteo error: {last_e}"

        assert False, self.output()

    def thoughts(self) -> str:
        return "Fetching weather forecast from Open-Meteo..."
