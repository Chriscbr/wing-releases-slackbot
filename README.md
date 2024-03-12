## Debugging

- When you are setting up the webhook on a GitHub repo's settings:
  - Make sure the content type is set to application/json
  - Make sure the URL has the full name the endpoint from the Wing application. When deployed to AWS it will be something like `https://xxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/payload`
  
