defmodule Erlef.Members do
  @moduledoc """
  Members context
  """

  alias Erlef.Repo
  alias Erlef.Members.EmailRequest
  alias Erlef.Members.EmailRequestNotification
  alias Erlef.Mailer
  alias Erlef.Admins

  import Ecto.Query

  def new_email_request(params \\ %{}) do
    EmailRequest.changeset(%EmailRequest{}, params)
  end

  def create_email_request(params) do
    result =
      params
      |> new_email_request()
      |> Repo.insert()

    case result do
      {:ok, _} ->
        Admins.notify(:new_email_request)
        result

      err ->
        err
    end
  end

  def get_email_request(id), do: Repo.get(EmailRequest, id)

  def has_email_request?(member) do
    case Repo.get_by(EmailRequest, submitted_by: member.id) do
      nil -> false
      _ -> true
    end
  end

  def get_email_request_by_member(member) do
    Repo.get_by(EmailRequest, submitted_by: member.id)
  end

  def update_email_request(%EmailRequest{} = req, params) do
    req
    |> EmailRequest.changeset(params)
    |> Repo.update()
  end

  def update_email_request(id, params) do
    case get_email_request(id) do
      %EmailRequest{} = req ->
        update_email_request(req, params)

      nil ->
        {:error, :not_found}
    end
  end

  def complete_email_request(%{id: id, password: password}) do
    with %EmailRequest{} = req <- get_email_request(id),
         {:ok, member} <- update_member_fields(req),
         {:ok, _req} <- update_email_request(req.id, %{status: :completed}) do
      notify(req, %{member: member, password: password})
    end
  end

  def complete_email_request(%{id: id}) do
    with %EmailRequest{} = req <- get_email_request(id),
         {:ok, member} <- update_member_fields(req),
         {:ok, req} <- update_email_request(req.id, %{status: :completed}) do
      notify(req, %{member: member})
    end
  end

  def outstanding_email_requests() do
    q =
      from(p in EmailRequest,
        where: p.status not in [:completed]
      )

    Repo.all(q)
  end

  def outstanding_email_requests_count() do
    q =
      from(p in EmailRequest,
        where: p.status not in [:completed],
        select: count(p.id)
      )

    Repo.one(q)
  end

  defp update_member_fields(req) do
    email = "#{req.username}@erlef.org"

    update =
      case req.type do
        :email_box ->
          %{erlef_email_address: email, has_email_box?: true, has_email_alias?: false}

        :email_alias ->
          %{erlef_email_address: email, has_email_box?: false, has_email_alias?: true}
      end

    case Erlef.Accounts.get_member(req.submitted_by) do
      {:ok, member} ->
        Erlef.Accounts.update_member(member, update)

      err ->
        err
    end
  end

  defp notify(%EmailRequest{type: :email_alias}, params) do
    {:ok, _} =
      params.member
      |> EmailRequestNotification.email_alias_created()
      |> Mailer.deliver()

    :ok
  end

  defp notify(%EmailRequest{type: :email_box}, params) do
    {:ok, _} =
      params.member
      |> EmailRequestNotification.email_box_created(params.password)
      |> Erlef.Mailer.deliver()

    :ok
  end
end
