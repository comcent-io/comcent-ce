<script lang="ts">
  import { page } from '$app/stores';
  import { env } from '$env/dynamic/public';
  import { getJson, postJson, putJson } from '$lib/http';
  import toast from 'svelte-french-toast';
  import { onMount } from 'svelte';
  let loadScript: any;
  import SkeletonLoadingList from '$lib/components/SkeletonLoadingList.svelte';
  import Button from '$lib/components/Button.svelte';
  import Card from '$lib/components/Card.svelte';
  import H6 from '$lib/components/html/H6.svelte';

  let alertThresholdBalance = 5;
  let balance = '...';
  let billingAddress: any = null;
  let isTopUp = false;
  let paypal: any;
  let topUpAmount: number;
  let loading = false;
  const { PUBLIC_PAYPAL_CLIENT_ID } = env;

  onMount(async () => {
    loading = true;
    ({ loadScript } = await import('@paypal/paypal-js'));
    const [alertResult, balanceResult, billingAddressResult] = await Promise.all([
      getJson<{ alertThresholdBalance: number }>(
        `/api/v2/${$page.params.subdomain}/billing/alert-threshold`,
      ),
      getJson<{ walletBalance: string }>(`/api/v2/${$page.params.subdomain}/billing/balance`),
      getJson(`/api/v2/${$page.params.subdomain}/billing/address`),
    ]);

    if (!alertResult.ok || !balanceResult.ok || !billingAddressResult.ok) {
      toast.error('Error occurred while fetching settings. Please try again later.');
      loading = false;
      return;
    }

    alertThresholdBalance = alertResult.data.alertThresholdBalance;
    balance = balanceResult.data.walletBalance;
    billingAddress = billingAddressResult.data;
    loading = false;
  });

  let saveProgress = false;
  async function onSave() {
    saveProgress = true;
    const result = await postJson(`/api/v2/${$page.params.subdomain}/billing/alert-threshold`, {
      alertThresholdBalance,
    });
    if (!result.ok) {
      toast.error('Error occurred while saving settings. Please try again later.');
      saveProgress = false;
      return;
    }

    toast.success('Updated successfully');
    saveProgress = false;
  }

  function validateTopUpAmount() {
    if (topUpAmount < 40) {
      toast.error('Top-up amount should be at least $40');
      return false;
    } else if (topUpAmount % 10 != 0) {
      toast.error('Top-up amount should be a multiple of $10');
      return false;
    }
    return true;
  }

  async function renderPaymentButton() {
    try {
      paypal = await loadScript({ clientId: PUBLIC_PAYPAL_CLIENT_ID });
    } catch (error: any) {
      toast.error('failed to load the PayPal JS SDK script', error.message);
    }

    if (paypal && !isTopUp) {
      try {
        await paypal
          .Buttons({
            style: {
              layout: 'vertical',
              color: 'blue',
              shape: 'rect',
              label: 'paypal',
              borderRadius: 10,
            },
            createOrder: function (data: any, actions: any) {
              if (!validateTopUpAmount()) {
                throw new Error('Invalid top-up amount');
              }
              return actions.order.create({
                payer: {
                  address: {
                    admin_area_2: billingAddress.city,
                    admin_area_1: billingAddress.state,
                    postal_code: billingAddress.postalCode,
                    country_code: billingAddress.country,
                  },
                },
                purchase_units: [
                  {
                    amount: {
                      currency_code: 'USD',
                      value: topUpAmount,
                    },
                  },
                ],
              });
            },
            onApprove: async function (data: any, actions: any) {
              toast.success(`Payment successful! Your balance has been updated.`);
              const orderId = data.orderID;
              await actions.order.capture();
              await updateWalletBalance(orderId);
            },
            onError: function (error: any) {
              if (error.message === 'Invalid top-up amount') {
                return;
              }
              toast.error(`Enter valid top up amount`);
            },
            onCancel: function () {
              toast.error('Payment cancelled');
            },
          })
          .render('#paypal-button-container');
        isTopUp = true;
      } catch (error: any) {
        toast.error('failed to render the PayPal Buttons', error.message);
      }
    }
  }

  async function updateWalletBalance(orderId: string) {
    const result = await putJson(`/api/v2/${$page.params.subdomain}/billing/balance`, {
      orderId,
      paymentGateway: 'Paypal',
    });
    if (!result.ok) {
      toast.error(result.error);
    }
  }
</script>

<h3 class="text-3xl font-bold dark:text-white my-4 mt-4">Balance</h3>
{#if loading}
  <SkeletonLoadingList />
{:else}
  <div class="flex gap-3 items-start">
    <Card className="w-1/2">
      <div class="flex flex-col justify-between h-full">
        <div class="flex flex-col items-center w-40 ml-48">
          <H6>Balance USD</H6>
          <H6>{balance}</H6>
          <input
            type="number"
            id="amount"
            name="amount"
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500 mt-4"
            placeholder="Amount to Top up"
            bind:value={topUpAmount}
          />
          <Button
            on:click={() => {
              if (validateTopUpAmount()) {
                renderPaymentButton();
              }
            }}
            className="mt-4"
          >
            Top Up
          </Button>
        </div>
        <div id="paypal-button-container" class="mt-4 w-96 ml-20"></div>
        <div class="flex flex-col items-center mb-5 mt-10 cursor-pointer">
          <label
            for="alertThresholdBalance"
            class="text-sm font-medium text-gray-900 dark:text-gray-300"
          >
            Get an alert when balance reaches ($):
          </label>
          <div class="flex w-full space-x-5 ml-80 mt-2">
            <input
              name="alertThresholdBalance"
              type="number"
              min="5"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-32 p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              bind:value={alertThresholdBalance}
            />
            <Button on:click={onSave} type="button" progress={saveProgress}>Save</Button>
          </div>
        </div>
      </div>
    </Card>
    <Card className="w-1/2">
      <h3 class="text-3xl font-bold dark:text-white">Billing Address</h3>
      {#if billingAddress}
        <div class="max-w-4xl mx-auto p-5 text-gray-500 dark:text-gray-400">
          <div class="mb-4">
            <p class="block font-bold mb-1">Country</p>
            <p>{billingAddress.country}</p>
          </div>
          <div class="mb-4">
            <p class="block font-bold mb-1">Line 1</p>
            <p>{billingAddress.line1}</p>
          </div>
          <div class="mb-4">
            <p class="block font-bold mb-1">City</p>
            <p>{billingAddress.city}</p>
          </div>
          <div class="mb-4">
            <p class="block font-bold mb-1">State</p>
            <p>{billingAddress.state}</p>
          </div>
          <div class="mb-4">
            <p class="block font-bold mb-1">Zip Code</p>
            <p>{billingAddress.postalCode}</p>
          </div>
        </div>
      {/if}
    </Card>
  </div>
{/if}
