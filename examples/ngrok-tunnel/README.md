# Example: ngrok tunnel

[Ngrok](https://ngrok.com) is a handy http tunnel you can use to expose your local environment to the Web and inspect incoming requests.

## Test the example

1. First, you will have to Sign up to your ngrok account. For this use case, the free plan is sufficient. Once it's done, on the left menu clic on "Getting Started > Your Auth token"

2. Copy this token to your own .env file (`mv .env.dist .env`)

3. Run PrestaShop Flashlight alongside a Ngrok agent:

```sh
❯ docker compose up --force-recreate -d
[+] Running 4/4
 ✔ Container flashlight-ngrok-tunnel-ngrok-1       Started                              0.6s
 ✔ Container flashlight-ngrok-tunnel-mysql-1       Healthy                             11.1s
 ✔ Container flashlight-ngrok-tunnel-phpmyadmin-1  Started                             11.2s
 ✔ Container flashlight-ngrok-tunnel-prestashop-1  Started
```

From the logs you can guess where to connect to:

- http://4452-37-170-242-21.ngrok.app

But you will also be redirected to the public URL by PrestaShop if you make a local call to:

- http://localhost:8000
