# Example: ngrok tunnel example

[Ngrok](https://ngrok.com) is a handy http tunnel you can use to expose your local environment to the Web and inspect incoming requests.

## Test the example

1. First you will have to Sign up to your ngrok account. For this simple use case the free plan is sufficient. Once it's done, on the left menu clic on "Getting Started > Your Authtoken".

3. Copy this token to the your own .env file (`mv .env.dist .env`)

4. Run PrestaShop Flashlight alongside with an Ngrok agent:

```sh
docker compose up prestashop
ngrok-tunnel-prestashop-1  | * Auto-detecting domain with ngrok client api on http://ngrok:4040...
ngrok-tunnel-prestashop-1  | * ngrok tunnel found running on 4452-37-170-242-21.ngrok.app
ngrok-tunnel-prestashop-1  | * Applying PS_DOMAIN (4452-37-170-242-21.ngrok.app) to the dump...
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

- http://4452-37-170-242-21.ngrok.app

But you will also be redirected to the public URL by PrestaShop if you make a local call to:

- http://localhost:8000
