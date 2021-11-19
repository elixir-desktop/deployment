defmodule Desktop.MacOSCategory do
  @moduledoc false
  def categories() do
    [
      "business",
      "developer-tools",
      "education",
      "entertainment",
      "finance",
      "games",
      "action-games",
      "adventure-games",
      "arcade-games",
      "board-games",
      "card-games",
      "casino-games",
      "dice-games",
      "educational-games",
      "family-games",
      "kids-games",
      "music-games",
      "puzzle-games",
      "racing-games",
      "role-playing-games",
      "simulation-games",
      "sports-games",
      "strategy-games",
      "trivia-games",
      "word-games",
      "graphics-design",
      "healthcare-fitness",
      "lifestyle",
      "medical",
      "music",
      "news",
      "photography",
      "productivity",
      "reference",
      "social-networking",
      "sports",
      "travel",
      "utilities",
      "video",
      "weather"
    ]
    |> Enum.map(fn cat -> "public.app-category." <> cat end)
  end
end
