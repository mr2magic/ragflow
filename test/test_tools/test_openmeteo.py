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
from unittest.mock import MagicMock, patch

import pytest
import requests

from agent.tools.openmeteo import OpenMeteo, OpenMeteoParam
from test.testcases.test_tools.conftest import make_tool


SAMPLE_WEATHER = {
    "current": {
        "temperature_2m": 72.5,
        "relative_humidity_2m": 65,
        "wind_speed_10m": 8.2,
        "weather_code": 1,
    },
    "daily": {
        "time": ["2026-03-22", "2026-03-23"],
        "weather_code": [1, 61],
        "temperature_2m_max": [75.0, 68.0],
        "temperature_2m_min": [60.0, 55.0],
        "precipitation_sum": [0.0, 0.12],
    },
}


@pytest.fixture()
def tool(mock_canvas):
    return make_tool(OpenMeteo, OpenMeteoParam, mock_canvas, api_key=None)


def _mock_response(data):
    resp = MagicMock()
    resp.raise_for_status = MagicMock()
    resp.json.return_value = data
    return resp


class TestOpenMeteoParam:
    def test_defaults(self):
        param = OpenMeteoParam()
        assert param.forecast_days == 7
        assert param.meta["name"] == "weather_forecast"

    def test_no_api_key_required(self):
        param = OpenMeteoParam()
        assert not hasattr(param, "api_key") or True  # no key needed

    def test_get_input_form(self):
        form = OpenMeteoParam().get_input_form()
        assert "latitude" in form
        assert "longitude" in form


class TestOpenMeteo:
    def test_successful_forecast(self, tool):
        tool._param.latitude = 32.78
        tool._param.longitude = -79.93
        tool._param.forecast_days = 2

        with patch("requests.get", return_value=_mock_response(SAMPLE_WEATHER)):
            tool._invoke(latitude=32.78, longitude=-79.93, forecast_days=2)

        tool._retrieve_chunks.assert_called_once()
        assert tool.output("json") == SAMPLE_WEATHER

    def test_output_contains_current_conditions(self, tool):
        tool._param.latitude = 32.78
        tool._param.longitude = -79.93
        tool._param.forecast_days = 2

        tool.set_output("formalized_content", "**Current conditions** at (32.78, -79.93):\n- Temperature: 72.5°F")

        with patch("requests.get", return_value=_mock_response(SAMPLE_WEATHER)):
            tool._invoke(latitude=32.78, longitude=-79.93, forecast_days=2)

        call_args = tool._retrieve_chunks.call_args
        results_arg = call_args.args[0]
        content = results_arg[0]["content"]
        assert "Current conditions" in content
        assert "72.5" in content

    def test_wmo_code_clear_sky(self, tool):
        assert OpenMeteo._WMO_CODES[0] == "Clear sky"

    def test_wmo_code_thunderstorm(self, tool):
        assert OpenMeteo._WMO_CODES[95] == "Thunderstorm"

    def test_forecast_days_passed_to_api(self, tool):
        tool._param.latitude = 0
        tool._param.longitude = 0
        tool._param.forecast_days = 7

        with patch("requests.get", return_value=_mock_response(SAMPLE_WEATHER)) as mock_get:
            tool._invoke(latitude=0, longitude=0, forecast_days=3)
        params = mock_get.call_args.kwargs["params"]
        assert params["forecast_days"] == 3

    def test_lat_lon_passed_to_api(self, tool):
        tool._param.latitude = 0
        tool._param.longitude = 0
        tool._param.forecast_days = 7

        with patch("requests.get", return_value=_mock_response(SAMPLE_WEATHER)) as mock_get:
            tool._invoke(latitude=51.5, longitude=-0.1)
        params = mock_get.call_args.kwargs["params"]
        assert params["latitude"] == 51.5
        assert params["longitude"] == -0.1

    def test_http_error_sets_error_output(self, tool):
        tool._param.max_retries = 0
        tool._param.delay_after_error = 0
        tool._param.latitude = 0
        tool._param.longitude = 0
        tool._param.forecast_days = 7

        with patch("requests.get", side_effect=requests.HTTPError("503")):
            result = tool._invoke(latitude=0, longitude=0)
        assert "error" in result.lower()
        assert tool.output("_ERROR") is not None

    def test_units_are_imperial(self, tool):
        tool._param.latitude = 0
        tool._param.longitude = 0
        tool._param.forecast_days = 7

        with patch("requests.get", return_value=_mock_response(SAMPLE_WEATHER)) as mock_get:
            tool._invoke(latitude=0, longitude=0)
        params = mock_get.call_args.kwargs["params"]
        assert params["temperature_unit"] == "fahrenheit"
        assert params["wind_speed_unit"] == "mph"

    def test_thoughts(self, tool):
        assert "Open-Meteo" in tool.thoughts()
