# MIM Robotics App Hosting Registry V1

Generated: 2026-06-02

## Purpose

Register the MIM Robotics LLC public website as a managed MIM app, with PythonAnywhere hosting status and local source structure visible in `/studio/apps`.

## App Identity

- App key: `mim_robotics`
- Display name: `MIM Robotics`
- Public URL: `https://www.mimrobots.com`
- Local source root: `E:/MIM Robotics/mimrobots.com`
- Runtime: PythonAnywhere Flask app
- Ecosystem role: MIM Robotics LLC public website and robotics presentation layer

## PythonAnywhere Verification

Environment keys are present locally:

- `PYTHONANYWHERE_USERNAME`
- `PYTHONANYWHERE_API_KEY`
- `PYTHONANYWHERE_DOMAIN`

Token value was not recorded in artifacts.

Validated:

- PythonAnywhere CPU API: 200
- PythonAnywhere webapps API: 200
- Public homepage: 200
- Homepage title present: true
- Domain: `www.mimrobots.com`

PythonAnywhere webapp facts:

- `www.mimrobots.com`
- enabled: true
- Python version: 3.10
- source directory: `/home/raine0001/mimrobots/MIMweb`
- virtualenv: `/home/raine0001/mimrobots/MIMweb/mimenv`

## Local Website Structure

Local app folder:

`E:/MIM Robotics/mimrobots.com`

Detected Flask structure:

- `run.py`
- `config.py`
- `requirements.txt`
- `app/__init__.py`
- `app/models.py`
- `app/routes/`
- `app/templates/`
- `app/static/`
- `app/agent/`
- `app/resources/`

Existing MIM hook:

- `app/agent/mim_agent.py`
- `app/agent/process_resources.py`
- resource embeddings path: `app/resources/embeddings.json`

## DB Construct

The local Flask models define tables including:

- `user`
- `conversation`
- `resource`
- `post`
- `feedback`
- `product`
- `category`
- `product_image`
- `product_variant`
- `discount`
- `stock`
- `background`
- `product_review`
- `excel_upload`
- `conversation_log`
- `order`
- `client`
- `inquiry`

The app uses `DATABASE_URI` through Flask SQLAlchemy.

Studio does not yet connect directly to the PythonAnywhere app database, so `/studio/apps` marks DB status as `external_declared`.

## Live Studio Validation

Validated:

- `GET /studio/api/apps/state`
- `GET /studio/apps`

MIM Robotics now reports:

- runtime: PythonAnywhere Flask app
- source status: scanned by TOD
- git status: not git repo
- DB status: external declared
- health: good
- next action: connect app database/reporting adapter

## Next Step

Modernize the public website and tie it directly to MIM:

1. Create project candidate: MIM Robotics Website Modernization.
2. Review current page/content/assets.
3. Build new creation/robotics-oriented information architecture.
4. Decide whether to keep PythonAnywhere or migrate to the same managed app foundation as other MIM apps.
5. Connect MIM assistant support/contact flow.
6. Connect app database/reporting adapter for users, inquiries, resources, products, and conversations.
