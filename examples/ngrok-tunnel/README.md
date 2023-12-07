# Example: ngrok tunnel example

Ngrok is a handy solution to expose your local environment to the Web. You can get information about this third-party solution on their official web page: https://ngrok.com.

## Test the example

1. First you will have to Sign up (it's free). Once it's done, on the left menu clic on "Getting Started > Your Authtoken".

2. Copy this token to the your own .env file (`mv .env.dist .env`)

3. Run PrestaShop Flashlight alongside with an Ngrok agent:

```sh
docker compose up prestashop
ngrok-tunnel-prestashop-1  | * Auto-detecting domain with ngrok client api on http://ngrok:4040...
ngrok-tunnel-prestashop-1  | * ngrok tunnel found running on 4452-37-170-242-21.ngrok-free.app
ngrok-tunnel-prestashop-1  | * Applying PS_DOMAIN (4452-37-170-242-21.ngrok-free.app) to the dump...
ngrok-tunnel-prestashop-1  | * Enabling SSL redirect to the dump...
ngrok-tunnel-prestashop-1  | * Checking MySQL connectivity...
ngrok-tunnel-prestashop-1  | * PHP PDO connectivity checked
ngrok-tunnel-prestashop-1  | * PrestaShop MySQL client configuration set
ngrok-tunnel-prestashop-1  | * Restoring MySQL dump...
ngrok-tunnel-prestashop-1  | * MySQL dump restored!
ngrok-tunnel-prestashop-1  | * No init script(s) found
ngrok-tunnel-prestashop-1  | * Starting php-fpm...
ngrok-tunnel-prestashop-1  | * Starting nginx...
ngrok-tunnel-prestashop-1  | * Nginx started
ngrok-tunnel-prestashop-1  | * No post script(s) found
```

From the logs you can guess where to connect to:

- http://4452-37-170-242-21.ngrok-free.app

But you will also be redirected to the public URL by PrestaShop if you make a local local to:

- http://localhost:8000
