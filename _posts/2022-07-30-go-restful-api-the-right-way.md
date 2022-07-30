---
layout: post
title: >
  Go RESTful APIs, The Practical Way
---

### Intro

I have started to study and work with Go; I have a good background in Python for the web. I am enjoying golang, and when I am learning about something new, I like to put my hands on it.

In the last few days, in my free time, I started to create a REST API applying the best practices that I have learned in the last years

### Libraries

* [Gin](https://github.com/gin-gonic/gin) for HTTP
* [gorm](https://github.com/go-gorm/gorm) for ORM
* [viper](https://github.com/spf13/viper) for configuration
* [zap](https://github.com/uber-go/zap) for logging
* [testify](https://github.com/stretchr/testify) for testing
* [go2hal](https://github.com/pmoule/go2hal) for HAL
* [problem](https://github.com/mschneider82/problem) for problem JSON
* [validator](https://github.com/go-playground/validator/v10) for validation
* [sqlmock](https://github.com/DATA-DOG/go-sqlmock) for SQL mocking

### Model

The model is used by the ORM, in this case, by [gorm](https://github.com/go-gorm/gorm) to turn structures into SQL statements. For example:

```go
type Workspace struct {
  ID        uuid.UUID      `gorm:"type:uuid;default:uuid_generate_v4()" json:"id"`
  Name      string         `gorm:"not null,type:text" json:"name"`
  CreatedAt time.Time      `gorm:"autoCreateTime" json:"created_at"`
  UpdatedAt time.Time      `gorm:"autoUpdateTime" json:"updated_at"`
  DeletedAt gorm.DeletedAt `gorm:"index,->" json:"-"`
}
```

* _ID_ is used as the primary key, using a random UUID instead of auto-increment integers.
* _Name_ is a property of the model, it could be anything under any name in finite quantities.
* _CreatedAt_ when the model was created handled by gorm automatically.
* _UpdatedAt_ when the model was updated, handled by gorm automatically.
* _DeletedAt_ this is how gorm handles soft-delete. It needs to be the type of gorm.DeletedAt.

### Repository

The repository is a design pattern that helps us with the [CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) operations.

Let's first define an interface:

```go
type Repository interface {
  Configure(*gorm.DB)
  List(after time.Time, limit int) (any, error)
  Get(id any) (any, error)
  Create(entity any) (any, error)
  Update(id any, entity any) (bool, error)
  Delete(id any) (bool, error)
}
```

Then their implementation using gorm as ORM:

```go
func (repository *WorkspaceRepository) List(after time.Time, limit int) (any, error) {
  var wc model.WorkspaceCollection
  order := "created_at"
  err := r.db.Limit(limit).Order(order).Where(fmt.Sprintf("%v > ?", order), after).Limit(limit).Find(&wc).Error

  return wc, err
}

func (repository *WorkspaceRepository) Get(id any) (any, error) {
  var w *model.Workspace

  err := r.db.Where("id = ?", id).First(&w).Error

  return w, err
}

func (repository *WorkspaceRepository) Create(entity any) (any, error) {
  w := entity.(*model.Workspace)

  err := r.db.Create(w).Error

  return w, err
}

func (repository *WorkspaceRepository) Update(id any, entity any) (bool, error) {
  w := entity.(*model.Workspace)

  if err := r.db.Model(w).Where("id = ?", id).Updates(w).Error; err != nil {
    return false, err
  }

  return true, nil
}

func (repository *WorkspaceRepository) Delete(id any) (bool, error) {
  if err := r.db.Delete(&model.Workspace{}, "id = ?", id).Error; err != nil {
    return false, err
  }

  return true, nil
}
```

### Routing

For handling HTTP routes, we need to create some functions which are called controllers, in this example, it is using [Gin](https://github.com/gin-gonic/gin).

```go
func (server *Server) registerRoutes() {
  var router = server.router

  workspaces := router.Group("/workspaces")
  {
    workspaces.GET("", GetWorkspaces)
    workspaces.POST("", CreateWorkspace)
    workspaces.GET("/:uuid", GetWorkspace)
    workspaces.PATCH("/:uuid", UpdateWorkspace)
    workspaces.DELETE("/:uuid", DeleteWorkspace)
  }
}
```

### Controller

The controllers are responsible to handle an HTTP call and return something useful, which can be a JSON with an object from the ORM or an error. Let's implement all CRUD operations:

```go
func GetWorkspaceRepository(ctx *gin.Context) repository.Repository {
  return ctx.MustGet("RepositoryRegistry").(*repository.RepositoryRegistry).MustRepository("WorkspaceRepository")
}

func GetWorkspaces(ctx *gin.Context) {
  var q = query{}

  if err := ctx.ShouldBindQuery(&q); err != nil {
    HandleError(err, ctx)
    return
  }

  entities, err := GetWorkspaceRepository(ctx).List(q.After, q.Limit)
  if err != nil {
    HandleError(err, ctx)
    return
  }

  WriteHAL(ctx, http.StatusOK, entities.(model.WorkspaceCollection).ToHAL(ctx.Request.URL.Path, ctx.Request.URL.Query()))
}

func GetWorkspace(ctx *gin.Context) {
  p := params{}

  ctx.ShouldBindUri(&p)

  if err := validate.Struct(p); err != nil {
    HandleError(err, ctx)
    return
  }

  entity, err := GetWorkspaceRepository(ctx).Get(p.ID)
  if err != nil {
    HandleError(err, ctx)
    return
  }

  WriteHAL(ctx, http.StatusOK, entity.(*model.Workspace).ToHAL(ctx.Request.URL.Path))
}

func CreateWorkspace(ctx *gin.Context) {
  body := model.Workspace{}

  if err := ctx.BindJSON(&body); err != nil {
    HandleError(err, ctx)
    return
  }

  entity, err := GetWorkspaceRepository(ctx).Create(&body)
  if err != nil {
    HandleError(err, ctx)
    return
  }

  workspace := entity.(*model.Workspace)
  selfHref, _ := url.JoinPath(ctx.Request.URL.Path, workspace.ID.String())
  WriteHAL(ctx, http.StatusCreated, workspace.ToHAL(selfHref))
}

func UpdateWorkspace(ctx *gin.Context) {
  p := params{}

  ctx.ShouldBindUri(&p)

  if err := validate.Struct(p); err != nil {
    HandleError(err, ctx)
    return
  }

  body := model.Workspace{}

  if err := ctx.BindJSON(&body); err != nil {
    HandleError(err, ctx)
    return
  }

  repository := GetWorkspaceRepository(ctx)

  _, err := repository.Update(p.ID, &body)
  if err != nil {
    HandleError(err, ctx)
    return
  }

  entity, err := repository.Get(p.ID)
  if err != nil {
    HandleError(err, ctx)
    return
  }

  WriteHAL(ctx, http.StatusOK, entity.(*model.Workspace).ToHAL(ctx.Request.URL.Path))
}

func DeleteWorkspace(ctx *gin.Context) {
  p := params{}

  ctx.ShouldBindUri(&p)

  if err := validate.Struct(p); err != nil {
    HandleError(err, ctx)
    return
  }

  _, err := GetWorkspaceRepository(ctx).Delete(p.ID)
  if err != nil {
    HandleError(err, ctx)
    return
  }

  WriteNoContent(ctx)
}
```

### HAL Links

>APIs are forever. Once an API is integrated into a production application, it is difficult to make significant changes that could potentially break those existing integrations

[Principles of Web API Design: Delivering Value with APIs and Microservices](https://www.amazon.com.br/Principles-Web-Design-James-Higginbotham/dp/0137355637)

In practice, it is hard to break an API contract because the API consumer will be mad at you. A new version of an API is not practical; nobody will move to another API. 

Thinking about that, [HAL Links](https://datatracker.ietf.org/doc/html/draft-kelly-json-hal-06), formally known as JSON Hypertext Application Language, try to solve API migration in a way without pain. Instead of using a hardcoded location to a resource, the API should return the representation of the resource in the _self_ field.

```json
{
  "_links": {
    "self": "/workspaces/6424f2b7-8094-48de-a68c-24bbb7de1faa"
  }
}

...

```

The implementatio is quite simple:

```go
func (model *Workspace) ToHAL(selfHref string) (root hal.Resource) {
  root = hal.NewResourceObject()
  root.AddData(model)

  selfRel := hal.NewSelfLinkRelation()
  selfLink := &hal.LinkObject{Href: selfHref}
  selfRel.SetLink(selfLink)
  root.AddLink(selfRel)

  return
}
```

### Problem Details

You probably have noted the `HandleError` function which is called on every error, this function is responsible to turn errors into something more meaningful by returning a `application/problem+json`

```go
func HandleError(err error, ctx *gin.Context) {
  var p *problem.Problem

  switch {
  case errors.Is(err, gorm.ErrRecordNotFound):
    p = problem.New(
      problem.Title("Record Not Found"),
      problem.Type("errors:database/record-not-found"),
      problem.Detail(err.Error()),
      problem.Status(http.StatusNotFound),
    )
    break
  default:
    p = problem.New(
      problem.Title("Bad Request"),
      problem.Type("errors:http/bad-request"),
      problem.Detail(err.Error()),
      problem.Status(http.StatusBadRequest),
    )
    break
  }

  p.WriteTo(ctx.Writer)
}
```

For example, if the `after` parameter is not in the RFC 3339 format. It will return an error

```shell
$ http localhost:8000/workspaces?after=0
HTTP/1.1 400 Bad Request
Content-Length: 164
Content-Type: application/problem+json
Date: Sat, 30 Jul 2022 18:23:54 GMT
{
    "detail": "parsing time \"0\" as \"2006-01-02T15:04:05Z07:00\": cannot parse \"0\" as \"2006\"",
    "status": 400,
    "title": "Bad Request",
    "type": "errors:http/bad-request"
}
```

Notice the `Content-Type`, it is the _mimetype_ of [Problem Details for HTTP APIs](https://datatracker.ietf.org/doc/html/rfc7807) with a detailed error in the body.


[Full example](https://github.com/skhaz/go-restful-api)