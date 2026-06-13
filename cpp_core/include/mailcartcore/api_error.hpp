#pragma once
#include <map>
#include <stdexcept>
#include <string>

namespace mailcartcore
{
  // Counterpart of FastAPI's HTTPException: carries the HTTP status, the
  // `detail` payload string, and optional response headers (WWW-Authenticate).
  class ApiError : public std::runtime_error
  { public:
    ApiError(int status, std::string detail, std::map<std::string, std::string> headers = {})
      : std::runtime_error(detail),
        status_(status),
        detail_(std::move(detail)),
        headers_(std::move(headers))
    {
    }

    [[nodiscard]] int status() const
    { return status_;
    }

    [[nodiscard]] const std::string &detail() const
    { return detail_;
    }

    [[nodiscard]] const std::map<std::string, std::string> &headers() const
    { return headers_;
    }

    private:
    int status_;
    std::string detail_;
    std::map<std::string, std::string> headers_;
  };
} // namespace mailcartcore
