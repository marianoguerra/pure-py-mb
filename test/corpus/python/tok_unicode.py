# Non-ASCII in identifiers and in strings. The column of a token after a
# multi-byte character is where the two column notions part company.
café = "caffè"
naïve = 'ünïcödé'
print(café, naïve, "héllo"[0], "🐍")
Δ = 1
π = 3.14
print(Δ, π)
