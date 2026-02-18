
import requests
import json
import sys

# Replace with your credentials or pass them as arguments
DEFAULT_EMAIL = "dev.luizg@gmail.com"
DEFAULT_PASSWORD = "Amor123*"

BASE_URL = "https://simuladoapp.com.br"
LOGIN_URL = f"{BASE_URL}/api/token/"

def test_login(email, password):
    print(f"Testing login for: {email}")
    print(f"Target URL: {LOGIN_URL}")
    
    headers = {
        'Content-Type': 'application/json'
    }
    
    payload = {
        'email': email,
        'password': password
    }
    
    try:
        response = requests.post(LOGIN_URL, json=payload, headers=headers)
        
        print(f"Status Code: {response.status_code}")
        print(f"Response Body: {response.text}")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 2:
        email = sys.argv[1]
        password = sys.argv[2]
    else:
        email = input("Enter email: ")
        password = input("Enter password: ")
        
    test_login(email, password)
