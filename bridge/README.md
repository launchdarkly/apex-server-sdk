# LaunchDarkly Apex SDK Salesforce Bridge

This daemon is used to ensure LaunchDarkly and the Salesforce SDK stay synchronized. The daemon can be built with `go build .`

## Configuration

The daemon uses environment variables for configuration. You must configure either the JWT or password based authentication.
JWT authentication is recommended but password authentication is easier for testing.

```bash
# The secrets in this example are randomly generated

# required configuration options
export LD_SDK_KEY='Your LaunchDarkly SDK key'
# such as: 'sdk-36f084b0-a57b-42a6-831e-1e20b7631b92'
export SALESFORCE_URL='Your Salesforce Apex REST URL'
# such as: 'https://na123.salesforce.com/services/apexrest/'
export OAUTH_ID='Your Salesforce OAuth Id'
# such as: 'BfBGjyY0.8XTDtB6enx5WXSATZ6mhPhnn.V2xK2Q8aYIW7KBS4r.7RA5QDbhaVOc4swvGZUqao-4X2S6Z-MdP'
export OAUTH_USERNAME='Your Salesforce username'
# such as: 'address@example.com'

# when utilizing JWT based auth
export OAUTH_JWT_KEY='Your RSA private key in PEM format base64 encoded'
# such as: cat private.key | base64 -w 0

# when utilizing password based auth
export OAUTH_SECRET='Your Salesforce OAuth secret'
# such as: '1193EEA95E6E26978D5BA60B103CC419FB653E314EA5BF282BDD1D429769685E'
export OAUTH_PASSWORD='Your Salesforce password + security token'
# such as: 'mypasswordmysalesforcesecuritytoken'

# optional configuration options
export OAUTH_URI='YOUR OAUTH URI'
# such as: 'https://login.salesforce.com/services/oauth2/token'
```