from fastapi import APIRouter

from app.api.dependencies import CurrentUser, DbSession
from app.core.security import create_access_token
from app.models.user import User
from app.schemas.auth_schema import RegisterIn, TokenOut, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenOut)
def register(body: RegisterIn, db: DbSession) -> TokenOut:
    user = db.query(User).filter_by(email=body.email).first()
    if not user:
        user = User(email=body.email)
        db.add(user)
        db.commit()
        db.refresh(user)
    return TokenOut(access_token=create_access_token(user.id))


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser) -> User:
    return user
