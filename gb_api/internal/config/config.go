package config


// JWT signing keys (load from env vars in production)
var JwtKey     = []byte("your_secret_key_keep_it_safe")
var RefreshKey = []byte("your_refresh_secret_keep_it_safe")
